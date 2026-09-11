import Foundation
import GanchoKit

/// One retention pass, the same on Mac and iPhone: purge what the policy has
/// expired, record the secrets that expired on the on-device activity receipt,
/// send the purge's deletions to iCloud, then enforce the tier's limits.
///
/// The order is the durable-write-before-sync boundary. The purge tombstones
/// every synced victim in the same transaction that deletes it, and only after
/// that write has committed are the pending deletions read back and enqueued, so
/// iCloud is never asked to delete a record the device still holds. The whole
/// tombstone table is swept, not just this pass's victims: re-adding a deletion
/// the engine already has pending is a no-op. Whether sync is on is asked after
/// the purge, so a toggle that lands while it runs is honored.
///
/// Every step is best effort, as in the two shells this replaced: a failed purge
/// records no expiry but still lets pending deletions propagate and the tier be
/// enforced, and a failed read of pending deletions enqueues nothing without
/// skipping the tier. Refreshing whatever list is on screen stays with the shell.
@MainActor
public struct RetentionPass {
    /// The store and sync side effects, injected so the pass is testable without
    /// a database or an iCloud account.
    public struct Steps {
        /// Deletes what the policy has expired as of the date, tombstoning synced
        /// victims first, and reports what it removed.
        public var purge: @MainActor (RetentionPolicy, Date) async throws -> PurgeSummary
        /// Adds the pass's expired secrets to the on-device activity receipt.
        public var recordSensitiveExpiry: @MainActor (_ count: Int, _ at: Date) async throws -> Void
        /// The record IDs whose deletion still has to reach iCloud.
        public var pendingDeletionRecordIDs: @MainActor () async throws -> [String]
        /// The engine that propagates deletions, or nil when sync is off.
        public var syncEngine: @MainActor () -> (any SyncEngine)?
        /// Applies the tier's limits once the purge is done.
        public var enforceTier: @MainActor (UserTier) async throws -> Void

        public init(
            purge: @escaping @MainActor (RetentionPolicy, Date) async throws -> PurgeSummary,
            recordSensitiveExpiry:
                @escaping @MainActor (_ count: Int, _ at: Date) async throws -> Void,
            pendingDeletionRecordIDs: @escaping @MainActor () async throws -> [String],
            syncEngine: @escaping @MainActor () -> (any SyncEngine)?,
            enforceTier: @escaping @MainActor (UserTier) async throws -> Void
        ) {
            self.purge = purge
            self.recordSensitiveExpiry = recordSensitiveExpiry
            self.pendingDeletionRecordIDs = pendingDeletionRecordIDs
            self.syncEngine = syncEngine
            self.enforceTier = enforceTier
        }

        /// The real steps over the app's store and sync controller.
        public static func live(store: GRDBClipboardStore, sync: SyncController) -> Steps {
            Steps(
                purge: { policy, now in
                    try await RetentionEngine(store: store).runPurge(policy: policy, now: now)
                },
                recordSensitiveExpiry: { count, at in
                    try await store.recordPrivateSensitiveExpiry(count: count, at: at)
                },
                pendingDeletionRecordIDs: { try await store.pendingDeletionRecordIDs() },
                syncEngine: { sync.isEnabled ? sync.engine : nil },
                enforceTier: { tier in
                    _ = try await TierEnforcement(store: store).enforce(tier: tier)
                })
        }
    }

    private let steps: Steps

    public init(steps: Steps) {
        self.steps = steps
    }

    /// Runs one pass.
    ///
    /// - Parameters:
    ///   - policy: The retention policy to apply.
    ///   - tier: The tier whose limits are enforced after the purge.
    ///   - now: The pass's clock, used for the purge and for the receipt entry.
    public func run(policy: RetentionPolicy, tier: UserTier, now: Date) async {
        if let summary = try? await steps.purge(policy, now) {
            try? await steps.recordSensitiveExpiry(summary.sensitiveExpired, now)
        }
        if let engine = steps.syncEngine() {
            let recordIDs = (try? await steps.pendingDeletionRecordIDs()) ?? []
            let ids = recordIDs.compactMap { UUID(uuidString: $0) }
            if !ids.isEmpty {
                await engine.enqueueDeletion(ids: ids)
            }
        }
        try? await steps.enforceTier(tier)
    }
}

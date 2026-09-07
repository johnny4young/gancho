import Foundation
import GanchoKit

/// One durable-write-before-sync boundary for deleting clips, shared by both
/// shells.
///
/// The rule this type exists to enforce: a CloudKit deletion is enqueued ONLY
/// for the ids whose local tombstone actually committed. Both shells previously
/// wrote the tombstone with `try?` and then enqueued the whole batch
/// unconditionally, so a failed local write still destroyed the record in
/// iCloud and on every other device while the clip survived on the device the
/// user deleted it from — a divergence nothing could repair, because the local
/// row that would re-upload it was never marked. `BoardsController` already
/// applies this ordering to boards; clips now share it.
///
/// A partial batch still propagates what it can: the successful ids are the
/// user's intent, and re-running the failures is safe because `deleteForSync`
/// is idempotent. The shells report failure content-free.
public struct ClipDeletionWorkflow: Sendable {
    /// What actually happened, so the shell can stay silent on success and
    /// surface a content-free diagnostic otherwise.
    public enum Outcome: Sendable, Equatable {
        /// Every id was removed locally. `propagated` is true when those
        /// removals were also enqueued for sync.
        case deleted(propagated: Bool)
        /// Some ids were removed; `failed` lists the ones that were not and
        /// were therefore never enqueued.
        case partial(failed: [UUID])
        /// No id could be removed. Nothing was enqueued.
        case failed
    }

    public init() {}

    /// Deletes `ids`, tombstoning first when sync is on.
    ///
    /// - Parameters:
    ///   - ids: the clips to delete, in the caller's order. Empty is a no-op
    ///     that reports `.deleted(propagated: false)` — nothing failed.
    ///   - store: the plain local delete used when sync is off.
    ///   - syncStore: the tombstoning surface. Nil means this build has no
    ///     durable store facet, so the plain path runs even with sync on —
    ///     preserving the shells' existing `guard let` behavior rather than
    ///     silently dropping the delete.
    ///   - engine: receives only the ids whose tombstone committed.
    ///   - syncEnabled: the live sync toggle.
    public func delete(
        ids: [UUID],
        store: any ClipboardStore,
        syncStore: (any ClipMutating)?,
        engine: any SyncEngine,
        syncEnabled: Bool,
        now: Date = .now
    ) async -> Outcome {
        guard !ids.isEmpty else { return .deleted(propagated: false) }

        guard syncEnabled, let syncStore else {
            var failed: [UUID] = []
            for id in ids {
                do { try await store.delete(id: id) } catch { failed.append(id) }
            }
            return Self.outcome(failed: failed, total: ids.count, propagated: false)
        }

        var committed: [UUID] = []
        var failed: [UUID] = []
        for id in ids {
            do {
                try await syncStore.deleteForSync(id: id, now: now)
                committed.append(id)
            } catch {
                failed.append(id)
            }
        }
        // The enqueue is the whole point of the ordering: only what is durably
        // gone locally may be removed from the user's other devices.
        if !committed.isEmpty {
            await engine.enqueueDeletion(ids: committed)
        }
        return Self.outcome(failed: failed, total: ids.count, propagated: !committed.isEmpty)
    }

    private static func outcome(failed: [UUID], total: Int, propagated: Bool) -> Outcome {
        if failed.isEmpty { return .deleted(propagated: propagated) }
        if failed.count == total { return .failed }
        return .partial(failed: failed)
    }
}

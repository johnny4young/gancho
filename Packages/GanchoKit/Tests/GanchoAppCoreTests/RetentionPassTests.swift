import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

/// What the pass did, in order, recorded across the async steps and the engine.
private actor Timeline {
    struct Expiry: Sendable, Equatable {
        let count: Int
        let at: Date
    }

    private(set) var events: [String] = []
    private(set) var expiries: [Expiry] = []
    private(set) var enqueued: [[UUID]] = []
    private(set) var enforcedTiers: [UserTier] = []

    func note(_ event: String) { events.append(event) }

    func noteExpiry(_ count: Int, at: Date) {
        events.append("record-expiry")
        expiries.append(Expiry(count: count, at: at))
    }

    func noteEnqueue(_ ids: [UUID]) {
        events.append("enqueue")
        enqueued.append(ids)
    }

    func noteTier(_ tier: UserTier) {
        events.append("enforce-tier")
        enforcedTiers.append(tier)
    }
}

/// A sync engine that only records the deletions it is handed.
private struct DeletionSpy: SyncEngine {
    let timeline: Timeline

    func start() async throws {}
    func stop() async {}
    func enqueue(_ items: [ClipItem]) async {}
    func enqueueDeletion(ids: [UUID]) async { await timeline.noteEnqueue(ids) }
    func enqueue(boards: [Pinboard]) async {}
    func enqueueBoardDeletion(ids: [UUID]) async {}
}

private struct StepFailure: Error {}

/// Flips during the purge, to show when the pass asks whether sync is on.
@MainActor
private final class SyncSwitch {
    var isOn = false
}

/// The retention pass both shells run. Every store and sync effect is a fake:
/// what must hold on any machine is the order, which count and clock reach the
/// receipt, when deletions are propagated, and that one failed step does not
/// silently skip the rest.
@MainActor
@Suite("Retention pass")
struct RetentionPassTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let tombstoned = UUID()
    /// Non-zero in every clause, so recording anything but the sensitive count shows.
    private let summary = PurgeSummary(
        expiredByOwnDate: 1, sensitiveExpired: 2, byKindWindow: 3, byGlobalWindow: 4)

    private func pass(
        _ timeline: Timeline,
        purgeResult: @escaping @MainActor () throws -> PurgeSummary,
        pendingIDs: @escaping @MainActor () throws -> [String],
        syncEngine: @escaping @MainActor () -> (any SyncEngine)?
    ) -> RetentionPass {
        RetentionPass(
            steps: .init(
                purge: { _, _ in
                    await timeline.note("purge")
                    return try purgeResult()
                },
                recordSensitiveExpiry: { count, at in await timeline.noteExpiry(count, at: at) },
                pendingDeletionRecordIDs: {
                    await timeline.note("read-pending")
                    return try pendingIDs()
                },
                syncEngine: syncEngine,
                enforceTier: { tier in await timeline.noteTier(tier) }))
    }

    private func run(
        purgeResult: @escaping @MainActor () throws -> PurgeSummary? = { nil },
        pendingIDs: @escaping @MainActor () throws -> [String]? = { nil },
        syncOn: Bool = true,
        tier: UserTier = .pro
    ) async -> Timeline {
        let timeline = Timeline()
        let spy = DeletionSpy(timeline: timeline)
        let summary = summary
        let tombstoned = tombstoned
        await pass(
            timeline,
            purgeResult: { try purgeResult() ?? summary },
            pendingIDs: { try pendingIDs() ?? [tombstoned.uuidString] },
            syncEngine: { syncOn ? spy : nil }
        ).run(policy: RetentionPolicy(), tier: tier, now: now)
        return timeline
    }

    @Test("Deletions are enqueued only after the purge has committed its tombstones")
    func purgeCommitsBeforeDeletionsAreEnqueued() async {
        let timeline = await run()

        #expect(
            await timeline.events == [
                "purge", "record-expiry", "read-pending", "enqueue", "enforce-tier"
            ])
        #expect(await timeline.enqueued == [[tombstoned]])
    }

    @Test("The receipt gets the pass's sensitive count, stamped with the pass's clock")
    func receiptRecordsTheSensitiveCountAtThePassTime() async {
        let timeline = await run()

        #expect(await timeline.expiries == [.init(count: 2, at: now)])
    }

    @Test("A failed purge records no expiry but still propagates and enforces the tier")
    func failedPurgeStillPropagatesAndEnforces() async {
        let timeline = await run(purgeResult: { throw StepFailure() })

        #expect(await timeline.events == ["purge", "read-pending", "enqueue", "enforce-tier"])
    }

    @Test("With sync off, nothing is read back or enqueued")
    func syncOffReadsAndEnqueuesNothing() async {
        let timeline = await run(syncOn: false)

        #expect(await timeline.events == ["purge", "record-expiry", "enforce-tier"])
    }

    @Test("Only record IDs that are real UUIDs are enqueued")
    func onlyValidRecordIDsAreEnqueued() async {
        let tombstoned = tombstoned
        let timeline = await run(pendingIDs: { ["not-a-uuid", tombstoned.uuidString] })

        #expect(await timeline.enqueued == [[tombstoned]])
    }

    @Test("No pending deletions means the engine is not called at all")
    func noPendingDeletionsEnqueuesNothing() async {
        let timeline = await run(pendingIDs: { [] })

        #expect(await timeline.events == ["purge", "record-expiry", "read-pending", "enforce-tier"])
    }

    @Test("A failed read of pending deletions enqueues nothing but still enforces the tier")
    func failedPendingReadStillEnforcesTheTier() async {
        let timeline = await run(pendingIDs: { throw StepFailure() })

        #expect(await timeline.events == ["purge", "record-expiry", "read-pending", "enforce-tier"])
    }

    @Test("Whether sync is on is asked after the purge, not before")
    func syncIsAskedAfterThePurge() async {
        let timeline = Timeline()
        let spy = DeletionSpy(timeline: timeline)
        let syncSwitch = SyncSwitch()
        let summary = summary
        let tombstoned = tombstoned
        await pass(
            timeline,
            purgeResult: {
                // Sync turns on while the purge runs.
                syncSwitch.isOn = true
                return summary
            },
            pendingIDs: { [tombstoned.uuidString] },
            syncEngine: { syncSwitch.isOn ? spy : nil }
        ).run(policy: RetentionPolicy(), tier: .free, now: now)

        #expect(await timeline.enqueued == [[tombstoned]])
    }

    @Test("The tier the caller passed is the one enforced", arguments: [UserTier.free, .pro])
    func enforcesTheGivenTier(tier: UserTier) async {
        let timeline = await run(tier: tier)

        #expect(await timeline.enforcedTiers == [tier])
    }
}

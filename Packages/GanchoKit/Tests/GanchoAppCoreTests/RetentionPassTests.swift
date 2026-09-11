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

    struct Purge: Sendable, Equatable {
        let policy: RetentionPolicy
        let at: Date
    }

    private(set) var events: [String] = []
    private(set) var purges: [Purge] = []
    private(set) var expiries: [Expiry] = []
    private(set) var enqueued: [[UUID]] = []
    private(set) var enforcedTiers: [UserTier] = []

    func note(_ event: String) { events.append(event) }

    func notePurge(_ policy: RetentionPolicy, at: Date) {
        events.append("purge")
        purges.append(Purge(policy: policy, at: at))
    }

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

/// The shell's tier, so a test can change it mid-pass the way a purchase does.
@MainActor
private final class TierBox {
    var tier: UserTier

    init(_ tier: UserTier) { self.tier = tier }
}

/// The retention pass both shells run. Every store and sync effect is a fake:
/// what must hold on any machine is the order, what the purge and the receipt
/// are given, when deletions are propagated, which tier is enforced and when it
/// is read, and that one failed step does not silently skip the rest.
@MainActor
@Suite("Retention pass")
struct RetentionPassTests {
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)
    private static let tombstoned = UUID()
    /// Non-zero in every clause, so recording anything but the sensitive count shows.
    private static let summary = PurgeSummary(
        expiredByOwnDate: 1, sensitiveExpired: 2, byKindWindow: 3, byGlobalWindow: 4)

    private func pass(
        _ timeline: Timeline,
        purgeResult: @escaping @MainActor () throws -> PurgeSummary = { summary },
        recordExpiry: @escaping @MainActor () throws -> Void = {},
        pendingIDs: @escaping @MainActor () throws -> [String] = { [tombstoned.uuidString] },
        syncEngine: @escaping @MainActor () -> (any SyncEngine)?,
        tierResult: @escaping @MainActor () -> TierEnforcement.Summary = { .init() }
    ) -> RetentionPass {
        RetentionPass(
            steps: .init(
                purge: { policy, at in
                    await timeline.notePurge(policy, at: at)
                    return try purgeResult()
                },
                recordSensitiveExpiry: { count, at in
                    await timeline.noteExpiry(count, at: at)
                    try recordExpiry()
                },
                pendingDeletionRecordIDs: {
                    await timeline.note("read-pending")
                    return try pendingIDs()
                },
                syncEngine: syncEngine,
                enforceTier: { tier in
                    await timeline.noteTier(tier)
                    return tierResult()
                }))
    }

    private func run(
        policy: RetentionPolicy = RetentionPolicy(),
        purgeResult: @escaping @MainActor () throws -> PurgeSummary = { summary },
        recordExpiry: @escaping @MainActor () throws -> Void = {},
        pendingIDs: @escaping @MainActor () throws -> [String] = { [tombstoned.uuidString] },
        syncOn: Bool = true,
        tier: UserTier = .pro,
        tierResult: @escaping @MainActor () -> TierEnforcement.Summary = { .init() }
    ) async -> (timeline: Timeline, changed: Bool) {
        let timeline = Timeline()
        let spy = DeletionSpy(timeline: timeline)
        let changed = await pass(
            timeline, purgeResult: purgeResult, recordExpiry: recordExpiry,
            pendingIDs: pendingIDs, syncEngine: { syncOn ? spy : nil }, tierResult: tierResult
        ).run(policy: policy, tier: { tier }, now: Self.now)
        return (timeline, changed)
    }

    @Test("Deletions are enqueued only after the purge has committed its tombstones")
    func purgeCommitsBeforeDeletionsAreEnqueued() async {
        let (timeline, _) = await run()

        #expect(
            await timeline.events == [
                "purge", "record-expiry", "read-pending", "enqueue", "enforce-tier"
            ])
        #expect(await timeline.enqueued == [[Self.tombstoned]])
    }

    @Test("The purge gets the caller's policy and the pass's clock")
    func purgeUsesTheCallersPolicyAndClock() async {
        // A policy no default can be mistaken for: a shorter secret lifetime is
        // exactly what a user who tightened retention expects to be honored.
        let policy = RetentionPolicy(global: .week, sensitiveLifetime: 60)
        let (timeline, _) = await run(policy: policy)

        #expect(await timeline.purges == [.init(policy: policy, at: Self.now)])
    }

    @Test("The receipt gets the pass's sensitive count, stamped with the pass's clock")
    func receiptRecordsTheSensitiveCountAtThePassTime() async {
        let (timeline, _) = await run()

        #expect(await timeline.expiries == [.init(count: 2, at: Self.now)])
    }

    @Test("A failed purge records no expiry but still propagates and enforces the tier")
    func failedPurgeStillPropagatesAndEnforces() async {
        let (timeline, _) = await run(purgeResult: { throw StepFailure() })

        #expect(await timeline.events == ["purge", "read-pending", "enqueue", "enforce-tier"])
    }

    @Test("A failed receipt write still propagates deletions and enforces the tier")
    func failedExpiryRecordStillPropagatesAndEnforces() async {
        let (timeline, _) = await run(recordExpiry: { throw StepFailure() })

        #expect(
            await timeline.events == [
                "purge", "record-expiry", "read-pending", "enqueue", "enforce-tier"
            ])
    }

    @Test("With sync off, nothing is read back or enqueued")
    func syncOffReadsAndEnqueuesNothing() async {
        let (timeline, _) = await run(syncOn: false)

        #expect(await timeline.events == ["purge", "record-expiry", "enforce-tier"])
    }

    @Test("Only record IDs that are real UUIDs are enqueued")
    func onlyValidRecordIDsAreEnqueued() async {
        let (timeline, _) = await run(pendingIDs: { ["not-a-uuid", Self.tombstoned.uuidString] })

        #expect(await timeline.enqueued == [[Self.tombstoned]])
    }

    @Test("No pending deletions means the engine is not called at all")
    func noPendingDeletionsEnqueuesNothing() async {
        let (timeline, _) = await run(pendingIDs: { [] })

        #expect(await timeline.events == ["purge", "record-expiry", "read-pending", "enforce-tier"])
    }

    @Test("A failed read of pending deletions enqueues nothing but still enforces the tier")
    func failedPendingReadStillEnforcesTheTier() async {
        let (timeline, _) = await run(pendingIDs: { throw StepFailure() })

        #expect(await timeline.events == ["purge", "record-expiry", "read-pending", "enforce-tier"])
    }

    @Test("Whether sync is on is asked after the purge, not before")
    func syncIsAskedAfterThePurge() async {
        let timeline = Timeline()
        let spy = DeletionSpy(timeline: timeline)
        let syncSwitch = SyncSwitch()
        await pass(
            timeline,
            purgeResult: {
                // Sync turns on while the purge runs.
                syncSwitch.isOn = true
                return Self.summary
            },
            syncEngine: { syncSwitch.isOn ? spy : nil }
        ).run(policy: RetentionPolicy(), tier: { .free }, now: Self.now)

        #expect(await timeline.enqueued == [[Self.tombstoned]])
    }

    @Test("The tier is read when enforcement runs, not when the pass starts")
    func tierIsReadWhenEnforcementRuns() async {
        let timeline = Timeline()
        let spy = DeletionSpy(timeline: timeline)
        let box = TierBox(.free)
        await pass(
            timeline,
            purgeResult: {
                // The purchase lands while the purge is running.
                box.tier = .pro
                return Self.summary
            },
            syncEngine: { spy }
        ).run(policy: RetentionPolicy(), tier: { box.tier }, now: Self.now)

        #expect(await timeline.enforcedTiers == [.pro])
    }

    @Test("The tier the caller passed is the one enforced", arguments: [UserTier.free, .pro])
    func enforcesTheGivenTier(tier: UserTier) async {
        let (timeline, _) = await run(tier: tier)

        #expect(await timeline.enforcedTiers == [tier])
    }

    @Test("A pass that purged rows reports a change")
    func purgedRowsReportAChange() async {
        let (_, changed) = await run()

        #expect(changed)
    }

    @Test("A pass that archived or released rows reports a change")
    func tierWorkReportsAChange() async {
        let (_, changed) = await run(
            purgeResult: { PurgeSummary() }, tierResult: { .init(archived: 1) })

        #expect(changed)
    }

    @Test("A pass that moved nothing reports no change")
    func idlePassReportsNoChange() async {
        let (_, changed) = await run(purgeResult: { PurgeSummary() })

        #expect(!changed, "an idle tick must not make the shell reload its list")
    }
}

import Foundation
import Testing

@testable import GanchoAppCore

/// A thread-safe order log so the sequential-execution assertions don't race.
private actor StepLog {
    private(set) var order: [String] = []
    private(set) var snapshotAtLastStep: [String] = []
    func record(_ name: String) { order.append(name) }
    /// Capture the order visible at the moment a step runs — used to prove a
    /// step observes every prior step's effect (i.e. execution is sequential).
    func snapshot() { snapshotAtLastStep = order }
}

@Suite("MaintenanceRunner — ordered, gated launch pipeline")
struct MaintenanceRunnerTests {
    @Test("Enabled steps run in declared order")
    func runsInOrder() async {
        let log = StepLog()
        let ran = await MaintenanceRunner().run([
            MaintenanceStep("backfill") { await log.record("backfill") },
            MaintenanceStep("embeddings") { await log.record("embeddings") },
            MaintenanceStep("spotlight") { await log.record("spotlight") }
        ])
        #expect(ran == ["backfill", "embeddings", "spotlight"])
        #expect(await log.order == ["backfill", "embeddings", "spotlight"])
    }

    @Test("A disabled step is skipped but the order of the rest holds")
    func skipsDisabledStep() async {
        let log = StepLog()
        let ran = await MaintenanceRunner().run([
            MaintenanceStep("backfill") { await log.record("backfill") },
            MaintenanceStep("embeddings", isEnabled: false) {
                await log.record("embeddings")
            },
            MaintenanceStep("spotlight") { await log.record("spotlight") }
        ])
        #expect(ran == ["backfill", "spotlight"])
        #expect(await log.order == ["backfill", "spotlight"])
    }

    @Test("Steps are sequential — each sees the previous one's effect")
    func stepsAreSequential() async {
        // If steps ran concurrently, `seen` could miss the earlier append; the
        // sequential contract guarantees each step observes all prior ones.
        let log = StepLog()
        await MaintenanceRunner().run([
            MaintenanceStep("first") { await log.record("first") },
            MaintenanceStep("second") { await log.record("second") },
            MaintenanceStep("last") { await log.snapshot() }
        ])
        #expect(await log.snapshotAtLastStep == ["first", "second"])
    }

    @Test("An empty pipeline is a no-op")
    func emptyPipelineRunsNothing() async {
        let ran = await MaintenanceRunner().run([])
        #expect(ran.isEmpty)
    }

    @Test("All-disabled pipeline runs nothing")
    func allDisabledRunsNothing() async {
        let ran = await MaintenanceRunner().run([
            MaintenanceStep("a", isEnabled: false) {},
            MaintenanceStep("b", isEnabled: false) {}
        ])
        #expect(ran.isEmpty)
    }
}

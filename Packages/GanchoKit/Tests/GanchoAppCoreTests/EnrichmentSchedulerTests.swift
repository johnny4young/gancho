import Testing

@testable import GanchoAppCore

/// Counts how many pieces of work overlap, so a test can assert the ceiling
/// rather than the timing.
private actor ConcurrencyWitness {
    private(set) var peak = 0
    private(set) var finished = 0
    private var current = 0
    private var resumers: [CheckedContinuation<Void, Never>] = []

    func enter() {
        current += 1
        peak = max(peak, current)
    }

    func leave() {
        current -= 1
        finished += 1
    }

    /// Parks the caller until `releaseAll()`, so several pieces of work are
    /// provably in flight at the same moment instead of finishing instantly.
    func hold() async {
        await withCheckedContinuation { resumers.append($0) }
    }

    func waiting() -> Int { resumers.count }

    func releaseAll() {
        for resumer in resumers { resumer.resume() }
        resumers.removeAll()
    }
}

@Suite("EnrichmentScheduler — bounded, in order")
struct EnrichmentSchedulerTests {
    @Test("Ten enrichments never run more than the limit at once")
    func neverExceedsTheLimit() async {
        let witness = ConcurrencyWitness()
        let scheduler = EnrichmentScheduler(limit: 2)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask {
                    await scheduler.run {
                        await witness.enter()
                        await witness.hold()
                        await witness.leave()
                    }
                }
            }
            // Drain by COMPLETIONS, not by the parked count: work can be
            // queued inside the scheduler and not yet parked, so a loop that
            // stopped at "nobody parked" would leave those tasks unreleased.
            while await witness.finished < 10 {
                await witness.releaseAll()
                await Task.yield()
            }
            await group.waitForAll()
        }

        let peak = await witness.peak
        #expect(peak == 2, "peak concurrency was \(peak)")
    }

    @Test("A slot is handed to the next waiter, so the count stays honest")
    func slotsAreHandedOver() async {
        let witness = ConcurrencyWitness()
        let scheduler = EnrichmentScheduler(limit: 1)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<4 {
                group.addTask {
                    await scheduler.run {
                        await witness.enter()
                        await witness.hold()
                        await witness.leave()
                    }
                }
            }
            while await witness.finished < 4 {
                await witness.releaseAll()
                await Task.yield()
            }
            await group.waitForAll()
        }

        let peak = await witness.peak
        #expect(peak == 1)
        // Every slot was released: nothing leaked a permit.
        let inFlight = await scheduler.inFlight
        #expect(inFlight == 0)
    }

    @Test("A limit below one is still one, never zero")
    func limitIsClamped() async {
        let scheduler = EnrichmentScheduler(limit: 0)
        let witness = ConcurrencyWitness()
        await scheduler.run { await witness.enter() }
        let peak = await witness.peak
        #expect(peak == 1, "a zero limit would otherwise deadlock every enrichment")
    }
}

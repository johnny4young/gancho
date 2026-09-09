import Foundation
import Testing

@testable import GanchoAppCore

/// Counts how many pieces of work overlap, so a test can assert the ceiling
/// rather than the timing.
private actor ConcurrencyWitness {
    private(set) var peak = 0
    private(set) var finished = 0
    /// Entry order, tagged by the caller — the FIFO assertion reads this.
    private(set) var entered: [Int] = []
    private var current = 0
    private var resumers: [CheckedContinuation<Void, Never>] = []

    func enter(_ tag: Int = 0) {
        current += 1
        peak = max(peak, current)
        entered.append(tag)
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

/// Polls `condition` until it holds or the bound elapses. Bounded so a broken
/// scheduler fails the test instead of hanging it; the assertion is on the
/// condition, never on how long it took.
private func waitUntil(
    _ condition: @Sendable () async -> Bool,
    within timeout: Duration = .seconds(5)
) async -> Bool {
    let deadline = ContinuousClock.now.advanced(by: timeout)
    while ContinuousClock.now < deadline {
        if await condition() { return true }
        try? await Task.sleep(for: .milliseconds(1))
    }
    return await condition()
}

@Suite("EnrichmentScheduler — bounded, in copy order, cancellable")
struct EnrichmentSchedulerTests {
    private let copiedAt = Date(timeIntervalSince1970: 1_000)

    @Test("Ten enrichments never run more than the limit at once")
    func neverExceedsTheLimit() async {
        let witness = ConcurrencyWitness()
        let scheduler = EnrichmentScheduler(limit: 2)

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<10 {
                group.addTask { [copiedAt] in
                    await scheduler.run(copiedAt: copiedAt) {
                        await witness.enter()
                        await witness.hold()
                        await witness.leave()
                    }
                }
            }

            // BOTH permits have to be provably occupied before anything is
            // released. Draining earlier could free the first parked task
            // before the second even entered, and a correct limit-of-two
            // scheduler would then record a peak of one — a green run that
            // proved nothing, and a red one that blamed the scheduler.
            let bothInFlight = await waitUntil { await witness.waiting() == 2 }
            #expect(bothInFlight, "the scheduler never had two enrichments in flight at once")

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
                group.addTask { [copiedAt] in
                    await scheduler.run(copiedAt: copiedAt) {
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

    @Test("Waiters run in copy order even when their tasks arrive reversed")
    func waitersRunInCopyOrder() async {
        // The defect this guards: both shells dispatch enrichment as an
        // unstructured `Task`, and those are not guaranteed to reach the actor
        // in creation order. Here the arrival order is forced to be the exact
        // REVERSE of the copy order, so a scheduler that served arrival order
        // would produce [3, 2, 1].
        let witness = ConcurrencyWitness()
        let scheduler = EnrichmentScheduler(limit: 1)
        let base = Date(timeIntervalSince1970: 1_000)

        await withTaskGroup(of: Void.self) { group in
            // Occupies the only slot so everything after it must queue.
            group.addTask {
                await scheduler.run(copiedAt: base) {
                    await witness.enter(0)
                    await witness.hold()
                    await witness.leave()
                }
            }
            #expect(await waitUntil { await witness.waiting() == 1 })

            // Enqueue newest-copy-first, one at a time: waiting for the queue
            // to grow before adding the next makes the arrival order a fact
            // rather than a race.
            for tag in [3, 2, 1] {
                group.addTask {
                    await scheduler.run(copiedAt: base.addingTimeInterval(Double(tag))) {
                        await witness.enter(tag)
                        await witness.hold()
                        await witness.leave()
                    }
                }
                let queued = await waitUntil { await scheduler.queueDepth == 4 - tag }
                #expect(queued, "waiter \(tag) never reached the queue")
            }

            while await witness.finished < 4 {
                await witness.releaseAll()
                await Task.yield()
            }
            await group.waitForAll()
        }

        let entered = await witness.entered
        #expect(entered == [0, 1, 2, 3], "served in \(entered), not copy order")
    }

    @Test("A caller cancelled while queued never runs, and gives its slot back")
    func cancellationSkipsQueuedWork() async {
        let witness = ConcurrencyWitness()
        let scheduler = EnrichmentScheduler(limit: 1)

        // Holds the only slot for the whole test.
        let blocker = Task { [copiedAt] in
            await scheduler.run(copiedAt: copiedAt) {
                await witness.enter(0)
                await witness.hold()
                await witness.leave()
            }
        }
        #expect(await waitUntil { await witness.waiting() == 1 })

        let queued = Task { [copiedAt] in
            await scheduler.run(copiedAt: copiedAt) { await witness.enter(1) }
        }
        #expect(
            await waitUntil { await scheduler.queueDepth == 1 },
            "the second caller never parked, so this proves nothing about cancellation")

        queued.cancel()
        await queued.value

        #expect(
            await waitUntil { await scheduler.queueDepth == 0 },
            "the cancelled waiter was left in the queue")
        let entered = await witness.entered
        #expect(entered == [0], "the cancelled work ran anyway: \(entered)")

        // The blocker still owns the only permit; releasing it must return the
        // count to zero rather than leaving one stranded on the cancelled path.
        await witness.releaseAll()
        await blocker.value
        let inFlight = await scheduler.inFlight
        #expect(inFlight == 0, "a permit leaked: \(inFlight) still in flight")
    }

    @Test("A limit below one is still one, never zero")
    func limitIsClamped() async {
        let scheduler = EnrichmentScheduler(limit: 0)
        let witness = ConcurrencyWitness()
        await scheduler.run(copiedAt: copiedAt) { await witness.enter() }
        let peak = await witness.peak
        #expect(peak == 1, "a zero limit would otherwise deadlock every enrichment")
    }
}

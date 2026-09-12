import Foundation
import Testing

@testable import GanchoAppCore

@MainActor
@Suite("SpotlightCoordinator — reconcile policy and failure routing")
struct SpotlightCoordinatorTests {
    /// Curation and clip changes stale the donated set; a board-only burst
    /// does not. This predicate is the whole "react to the right mutations"
    /// rule, so it is the thing worth pinning.
    @Test("Reacts to curation and clips, ignores board-only bursts")
    func reactsToTheRightChanges() {
        #expect(SpotlightCoordinator.reactsTo([.curation]))
        #expect(SpotlightCoordinator.reactsTo([.clips]))
        #expect(SpotlightCoordinator.reactsTo([.boards, .curation]))
        #expect(SpotlightCoordinator.reactsTo([.clips, .boards]))
        #expect(!SpotlightCoordinator.reactsTo([.boards]))
        #expect(!SpotlightCoordinator.reactsTo([]))
    }

    @Test("A landed reconcile records no failure")
    func landedReconcileIsQuiet() async {
        var failures = 0
        let coordinator = SpotlightCoordinator(
            coalescer: SpotlightCoordinator.defaultCoalescer,
            reconcile: { true }, onFailure: { failures += 1 })
        await coordinator.reconcileNow()
        #expect(failures == 0)
    }

    @Test("A failed index write is routed to onFailure")
    func failedReconcileIsReported() async {
        var failures = 0
        let coordinator = SpotlightCoordinator(
            coalescer: SpotlightCoordinator.defaultCoalescer,
            reconcile: { false }, onFailure: { failures += 1 })
        await coordinator.reconcileNow()
        #expect(failures == 1)
    }

    @Test("No store yet is a silent skip, not a failure")
    func missingStoreSkipsSilently() async {
        var failures = 0
        let coordinator = SpotlightCoordinator(
            coalescer: SpotlightCoordinator.defaultCoalescer,
            reconcile: { nil }, onFailure: { failures += 1 })
        await coordinator.reconcileNow()
        #expect(failures == 0)
    }

    @Test("A relevant burst on the bus drives exactly one reconcile")
    func busBurstReconcilesOnce() async {
        let bus = StoreChangeBus()
        var reconciles = 0
        // The debounce is injected; wait for observable completion below.
        let coordinator = SpotlightCoordinator(
            coalescer: StoreChangeCoalescer(window: .zero, sleep: { _ in await Task.yield() }),
            reconcile: {
                reconciles += 1
                return true
            }, onFailure: {})
        coordinator.start(subscribingTo: bus)
        for _ in 0..<10 { bus.post(.curation) }
        let reconciled = await waitUntil { reconciles > 0 }
        coordinator.stop()
        #expect(reconciled, "the subscriber must process the posted burst")
        #expect(reconciles == 1, "a single burst must drive exactly one reconcile")
    }

    @Test("Starting again replaces the previous bus subscription")
    func restartingReplacesSubscription() async {
        let firstBus = StoreChangeBus()
        let secondBus = StoreChangeBus()
        let coordinator = SpotlightCoordinator(
            coalescer: SpotlightCoordinator.defaultCoalescer,
            reconcile: { true }, onFailure: {})

        coordinator.start(subscribingTo: firstBus)
        #expect(firstBus.subscriberCount == 1)
        coordinator.start(subscribingTo: secondBus)

        let unsubscribed = await waitUntil { firstBus.subscriberCount == 0 }
        #expect(unsubscribed, "the canceled subscription must terminate")
        #expect(firstBus.subscriberCount == 0)
        #expect(secondBus.subscriberCount == 1)
        coordinator.stop()
    }

    @Test("A board-only burst drives no reconcile")
    func boardOnlyBurstIsIgnored() async {
        let bus = StoreChangeBus()
        var reconciles = 0
        let coordinator = SpotlightCoordinator(
            coalescer: StoreChangeCoalescer(window: .zero, sleep: { _ in }),
            reconcile: {
                reconciles += 1
                return true
            }, onFailure: {})
        coordinator.start(subscribingTo: bus)
        bus.post(.boards)
        try? await Task.sleep(for: .milliseconds(50))
        coordinator.stop()
        #expect(reconciles == 0)
    }

    /// Task.yield() may immediately resume a higher-priority test instead of
    /// the utility-priority subscriber. Suspend between condition checks so
    /// the producer gets scheduled; a deadline still fails a lost event.
    private func waitUntil(_ condition: @MainActor () -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition(), ContinuousClock.now < deadline {
            do { try await Task.sleep(for: .milliseconds(10)) } catch { return false }
        }
        return condition()
    }

}

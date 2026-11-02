import Testing

@testable import ClipboardCore

@Suite("AdaptivePollingPolicy — mode transitions")
struct AdaptivePollingPolicyTests {
    let policy = AdaptivePollingPolicy()

    @Test("Recent input keeps the loop active at 250ms")
    func activeMode() {
        let mode = policy.mode(secondsSinceLastUserInput: 0.5, isScreenLocked: false)
        #expect(mode == .active)
        #expect(policy.interval(for: mode) == .milliseconds(250))
    }

    @Test("Stale input demotes to idle within the 1–2s budget")
    func idleMode() {
        let mode = policy.mode(secondsSinceLastUserInput: 31, isScreenLocked: false)
        #expect(mode == .idle)
        let interval = policy.interval(for: mode)
        #expect(interval >= .seconds(1) && interval <= .seconds(2))
    }

    @Test("Exactly at the idle threshold counts as idle")
    func idleThresholdBoundary() {
        #expect(policy.mode(secondsSinceLastUserInput: 30, isScreenLocked: false) == .idle)
        #expect(policy.mode(secondsSinceLastUserInput: 29.999, isScreenLocked: false) == .active)
    }

    @Test("Screen lock pauses polling even with fresh input")
    func lockWins() {
        let mode = policy.mode(secondsSinceLastUserInput: 0, isScreenLocked: true)
        #expect(mode == .paused)
    }

    @Test("Paused mode still returns a probe cadence so unlock is noticed")
    func pausedProbe() {
        #expect(policy.interval(for: .paused) == .seconds(2))
    }

    @Test("After a change the loop bursts inside the window, never while paused")
    func burstAfterChange() {
        #expect(
            policy.interval(for: .active, sinceLastChange: .milliseconds(100))
                == policy.burstInterval)
        #expect(
            policy.interval(for: .idle, sinceLastChange: .milliseconds(100))
                == policy.burstInterval)
        #expect(
            policy.interval(for: .active, sinceLastChange: policy.burstWindow)
                == policy.activeInterval)
        #expect(policy.interval(for: .active, sinceLastChange: nil) == policy.activeInterval)
        #expect(
            policy.interval(for: .paused, sinceLastChange: .milliseconds(100))
                == policy.pausedProbeInterval)
    }
}

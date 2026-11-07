#if os(macOS)
    import AppKit
    import Testing

    @testable import GanchoAppCore

    /// Hand-cranked checks: the tests fire them, so no wall-clock time passes.
    @MainActor
    private final class CheckClock {
        final class Pending {
            let delay: TimeInterval
            let tolerance: TimeInterval
            let action: @MainActor @Sendable () -> Void
            var isLive = true

            init(
                delay: TimeInterval, tolerance: TimeInterval,
                action: @escaping @MainActor @Sendable () -> Void
            ) {
                self.delay = delay
                self.tolerance = tolerance
                self.action = action
            }
        }

        private(set) var scheduled: [Pending] = []
        var live: [Pending] { scheduled.filter(\.isLive) }

        func schedule(
            _ delay: TimeInterval, _ tolerance: TimeInterval,
            _ action: @escaping @MainActor @Sendable () -> Void
        ) -> @MainActor () -> Void {
            let pending = Pending(delay: delay, tolerance: tolerance, action: action)
            scheduled.append(pending)
            return { pending.isLive = false }
        }

        func fire() {
            guard let pending = live.last else {
                Issue.record("no check is pending")
                return
            }
            pending.isLive = false
            pending.action()
        }
    }

    @MainActor
    private final class Affordance {
        var isPresent = true
        var lostCount = 0
    }

    @Suite("Menu-bar affordance watchdog — events, with a slow check at rest")
    @MainActor
    struct MenuBarAffordanceWatchdogTests {
        private let timing = MenuBarAffordanceWatchdog.Timing(afterEvent: 1, idle: 10)

        private func makeWatchdog(
            _ affordance: Affordance, _ clock: CheckClock
        ) -> MenuBarAffordanceWatchdog {
            MenuBarAffordanceWatchdog(
                isPresent: { affordance.isPresent },
                onLost: { affordance.lostCount += 1 },
                timing: timing,
                schedule: clock.schedule)
        }

        @Test("The first check comes one event delay after start, then it rests")
        func startsWithAnEventCheckThenRests() {
            let affordance = Affordance()
            let clock = CheckClock()
            let watchdog = makeWatchdog(affordance, clock)
            watchdog.start()
            #expect(clock.live.map(\.delay) == [1])

            clock.fire()
            clock.fire()

            #expect(clock.live.map(\.delay) == [10])
            #expect(clock.live.map(\.tolerance) == [1])
            #expect(affordance.lostCount == 0)
        }

        @Test("An event replaces the slow check with one an event delay away")
        func anEventBringsTheCheckForward() {
            let affordance = Affordance()
            let clock = CheckClock()
            let watchdog = makeWatchdog(affordance, clock)
            watchdog.start()
            clock.fire()

            watchdog.affordanceMayHaveChanged()

            #expect(clock.live.map(\.delay) == [1])
            #expect(clock.live.map(\.tolerance) == [0])
        }

        @Test("A burst of events never brings a pending event check closer")
        func aBurstKeepsThePendingCheck() {
            let affordance = Affordance()
            let clock = CheckClock()
            let watchdog = makeWatchdog(affordance, clock)
            watchdog.start()
            clock.fire()

            watchdog.affordanceMayHaveChanged()
            watchdog.affordanceMayHaveChanged()
            watchdog.affordanceMayHaveChanged()

            #expect(clock.scheduled.count == 3, "start, rest, one event check")
            #expect(clock.live.count == 1)
        }

        @Test("An announced loss is reported at the event check, once")
        func anAnnouncedLossIsReportedOnce() {
            let affordance = Affordance()
            let clock = CheckClock()
            let watchdog = makeWatchdog(affordance, clock)
            watchdog.start()
            clock.fire()

            affordance.isPresent = false
            watchdog.affordanceMayHaveChanged()
            clock.fire()

            #expect(affordance.lostCount == 1)
            #expect(clock.live.isEmpty)
            watchdog.affordanceMayHaveChanged()
            #expect(clock.live.isEmpty, "nothing runs after the loss")
        }

        @Test("A loss no event announced is caught by the slow check")
        func aSilentLossIsCaughtAtRest() {
            let affordance = Affordance()
            let clock = CheckClock()
            let watchdog = makeWatchdog(affordance, clock)
            watchdog.start()
            clock.fire()

            affordance.isPresent = false
            #expect(clock.live.map(\.delay) == [10])
            clock.fire()

            #expect(affordance.lostCount == 1)
        }

        @Test("Stop cancels the pending check and ignores later events")
        func stopCancels() {
            let affordance = Affordance()
            let clock = CheckClock()
            let watchdog = makeWatchdog(affordance, clock)
            watchdog.start()
            watchdog.stop()
            watchdog.affordanceMayHaveChanged()

            #expect(clock.live.isEmpty)
            #expect(affordance.lostCount == 0)
        }

        // Pins the trade-off on purpose: changing it is a product decision.
        @Test("Standard timing keeps 0.75 s after an event and checks every 5 s at rest")
        func standardTiming() {
            #expect(MenuBarAffordanceWatchdog.Timing.standard.afterEvent == 0.75)
            #expect(MenuBarAffordanceWatchdog.Timing.standard.idle == 5)
        }

        @Test("The sentinel reports its host leaving and joining a window, unseen")
        func sentinelReportsWindowChanges() {
            var changes = 0
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 40, height: 20), styleMask: .borderless,
                backing: .buffered, defer: true)
            let host = NSView(frame: NSRect(x: 0, y: 0, width: 20, height: 20))
            let sentinel = WindowChangeSentinel { changes += 1 }
            host.addSubview(sentinel)
            #expect(changes == 0)

            window.contentView?.addSubview(host)
            #expect(changes == 1)
            host.removeFromSuperview()
            #expect(changes == 2)
            #expect(sentinel.isHidden)
            #expect(!sentinel.isAccessibilityElement())
        }
    }
#endif

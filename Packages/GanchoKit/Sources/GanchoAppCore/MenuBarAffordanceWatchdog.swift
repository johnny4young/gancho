#if os(macOS)
    import AppKit

    /// Ties the clipboard-history process to its menu-bar icon: the first check
    /// that finds the icon gone reports the loss, once. An event that can take
    /// the icon away brings a check `afterEvent` later; at rest a slow check
    /// covers a loss no event announced.
    @MainActor
    public final class MenuBarAffordanceWatchdog {
        public struct Timing: Equatable, Sendable {
            public var afterEvent: TimeInterval
            public var idle: TimeInterval

            public init(afterEvent: TimeInterval, idle: TimeInterval) {
                self.afterEvent = afterEvent
                self.idle = idle
            }

            /// An announced loss keeps the 0.75 s bound; a silent one waits for the
            /// next slow check, 5 s plus up to 10 % tolerance.
            public static let standard = Timing(afterEvent: 0.75, idle: 5)
        }

        /// Runs `action` once after `delay`; the returned closure cancels it.
        public typealias Schedule =
            @MainActor (
                _ delay: TimeInterval, _ tolerance: TimeInterval,
                _ action: @escaping @MainActor @Sendable () -> Void
            ) -> @MainActor () -> Void

        private let isPresent: @MainActor () -> Bool
        private let onLost: @MainActor () -> Void
        private let timing: Timing
        private let schedule: Schedule
        private var cancelPending: (@MainActor () -> Void)?
        private var pendingIsEventCheck = false
        private var isRunning = false

        public init(
            isPresent: @escaping @MainActor () -> Bool,
            onLost: @escaping @MainActor () -> Void,
            timing: Timing = .standard,
            schedule: @escaping Schedule = MenuBarAffordanceWatchdog.runLoopTimer
        ) {
            self.isPresent = isPresent
            self.onLost = onLost
            self.timing = timing
            self.schedule = schedule
        }

        public func start() {
            isRunning = true
            arm(eventCheck: true)
        }

        /// A burst never brings a pending event check closer, so a menu bar
        /// being rebuilt still gets the full `afterEvent` to settle.
        public func affordanceMayHaveChanged() {
            guard isRunning, !pendingIsEventCheck else { return }
            arm(eventCheck: true)
        }

        public func stop() {
            isRunning = false
            cancelPending?()
            cancelPending = nil
        }

        private func check() {
            cancelPending = nil
            guard isRunning else { return }
            guard isPresent() else {
                stop()
                onLost()
                return
            }
            arm(eventCheck: false)
        }

        private func arm(eventCheck: Bool) {
            cancelPending?()
            pendingIsEventCheck = eventCheck
            let delay = eventCheck ? timing.afterEvent : timing.idle
            cancelPending = schedule(delay, eventCheck ? 0 : delay / 10) { [weak self] in
                self?.check()
            }
        }

        /// Common modes, so checks still run while a menu is tracking.
        public static func runLoopTimer(
            delay: TimeInterval, tolerance: TimeInterval,
            action: @escaping @MainActor @Sendable () -> Void
        ) -> @MainActor () -> Void {
            let timer = Timer(timeInterval: delay, repeats: false) { _ in
                MainActor.assumeIsolated { action() }
            }
            timer.tolerance = tolerance
            RunLoop.main.add(timer, forMode: .common)
            return { timer.invalidate() }
        }
    }

    /// A hidden subview that reports each time its host moves to or out of a
    /// window; AppKit posts nothing when a status button loses its window.
    public final class WindowChangeSentinel: NSView {
        private let onChange: @MainActor () -> Void

        public init(onChange: @escaping @MainActor () -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
            isHidden = true
            setAccessibilityElement(false)
        }

        @available(*, unavailable)
        public required init?(coder: NSCoder) { fatalError("Use init(onChange:)") }

        override public func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            onChange()
        }
    }
#endif

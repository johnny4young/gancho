#if os(macOS)
    import ClipboardCore
    import Foundation
    import Observation

    /// The narrow monitor surface required by the macOS capture lifecycle.
    /// Keeping the controller on this capability makes its state and timing
    /// behavior testable without an AppKit pasteboard or a running application.
    @MainActor
    public protocol CaptureMonitoring: AnyObject {
        var preferences: CapturePreferences { get set }
        var status: MonitorStatus { get }
        var pausedForScreenShare: Bool { get set }

        func start()
        func stop()
        func ignoreNextCopy()
    }

    extension MacPasteboardMonitor: CaptureMonitoring {}

    /// Owns the macOS capture lifecycle that the application facade presents:
    /// monitor start/stop, observable status mirroring, persisted preferences,
    /// private-mode toggling, one-shot ignore, and screen-share auto-pause.
    ///
    /// The monitor continues to own pasteboard reads and privacy vetoes. This
    /// controller only coordinates its lifecycle and never handles clip content.
    /// Explicit main-actor isolation preserves the app target's former execution
    /// context when this behavior lived directly in `AppModel`.
    @Observable
    @MainActor
    public final class CaptureLifecycleController {
        public private(set) var status: MonitorStatus

        public var preferences: CapturePreferences {
            didSet {
                // The observed property re-enters `didSet` on the stamp below;
                // the outer call finishes the work once.
                guard !isStamping else { return }
                if preferences.isPrivateModePaused != oldValue.isPrivateModePaused {
                    isStamping = true
                    preferences = stamped(preferences)
                    isStamping = false
                }
                monitor.preferences = preferences
                onPreferencesChanged(preferences)
                // The TRANSITION, not the current value: every Settings toggle
                // lands in this didSet, and work that tears down in-flight
                // state must not run again each time Private Mode merely
                // happens to be on.
                if preferences.isPrivateModePaused, !oldValue.isPrivateModePaused {
                    onPrivateModeEngaged()
                }
            }
        }

        public var autoPauseOnScreenShare: Bool {
            didSet { onAutoPauseChanged(autoPauseOnScreenShare) }
        }

        @ObservationIgnored private let monitor: any CaptureMonitoring
        @ObservationIgnored private let screenShareIsActive: @MainActor () -> Bool
        @ObservationIgnored private let onPreferencesChanged:
            @MainActor (CapturePreferences) -> Void
        /// Fired only as Private Mode goes off → on, for work that tears down
        /// what is already in flight. `onPreferencesChanged` fires on every
        /// save and is the wrong place for it.
        @ObservationIgnored private let onPrivateModeEngaged: @MainActor () -> Void
        @ObservationIgnored private let onAutoPauseChanged: @MainActor (Bool) -> Void
        @ObservationIgnored private var isStamping = false
        @ObservationIgnored private let now: @MainActor () -> Date
        /// How long a new Private Mode lasts; nil keeps it on until turned off.
        @ObservationIgnored private let privateModeDuration: @MainActor () -> TimeInterval?
        @ObservationIgnored private var statusTimer: Timer?
        @ObservationIgnored private var screenShareTimer: Timer?

        public init(
            monitor: any CaptureMonitoring,
            preferences: CapturePreferences,
            autoPauseOnScreenShare: Bool,
            screenShareIsActive: @escaping @MainActor () -> Bool,
            onPreferencesChanged: @escaping @MainActor (CapturePreferences) -> Void = { _ in },
            onPrivateModeEngaged: @escaping @MainActor () -> Void = {},
            onAutoPauseChanged: @escaping @MainActor (Bool) -> Void = { _ in },
            now: @escaping @MainActor () -> Date = { Date() },
            privateModeDuration: @escaping @MainActor () -> TimeInterval? = { 3_600 }
        ) {
            self.monitor = monitor
            self.preferences = preferences
            self.autoPauseOnScreenShare = autoPauseOnScreenShare
            self.screenShareIsActive = screenShareIsActive
            self.onPreferencesChanged = onPreferencesChanged
            self.onPrivateModeEngaged = onPrivateModeEngaged
            self.onAutoPauseChanged = onAutoPauseChanged
            self.now = now
            self.privateModeDuration = privateModeDuration
            status = monitor.status
            monitor.preferences = preferences
        }

        /// Starts capture and the same lightweight status/screen-share timers
        /// formerly scheduled by `AppModel`. Screen-share detection intentionally
        /// waits for its first three-second tick, preserving launch timing.
        public func activate() {
            invalidateTimers()
            // A deadline that passed while the app was closed ends Private Mode
            // before the first capture turn.
            expirePrivateModeIfDue()
            monitor.start()
            refreshStatus()
            statusTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) {
                [weak self] _ in
                Task { @MainActor in self?.refreshStatus() }
            }
            screenShareTimer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) {
                [weak self] _ in
                Task { @MainActor in self?.refreshScreenSharePause() }
            }
        }

        public func deactivate() {
            invalidateTimers()
            monitor.stop()
            refreshStatus()
        }

        public func startCapture() {
            monitor.start()
            refreshStatus()
        }

        public func stopCapture() {
            monitor.stop()
            refreshStatus()
        }

        public func toggleCapture() {
            if monitor.status == .running {
                monitor.stop()
            } else {
                monitor.start()
            }
            refreshStatus()
        }

        public func togglePrivateMode() {
            preferences.isPrivateModePaused.toggle()
        }

        public func ignoreNextCopy() {
            monitor.ignoreNextCopy()
        }

        /// Counts one copy made while Private Mode is on. The monitor reports
        /// it from the change count and the type list; its content is never read.
        public func notePrivateModeCopy() {
            guard preferences.isPrivateModePaused else { return }
            preferences.privateModeSkippedCopies += 1
        }

        /// Turns Private Mode off once its deadline passes. Runs on the status
        /// timer, so it fires within half a second of the deadline.
        func expirePrivateModeIfDue() {
            guard preferences.isPrivateModePaused, let end = preferences.privateModeEndsAt,
                now() >= end
            else { return }
            preferences.isPrivateModePaused = false
        }

        /// A Private Mode that just turned on starts its clock and count; one
        /// that turned off forgets them.
        private func stamped(_ preferences: CapturePreferences) -> CapturePreferences {
            var stamped = preferences
            let engaged = preferences.isPrivateModePaused
            let start = now()
            stamped.privateModeStartedAt = engaged ? start : nil
            stamped.privateModeEndsAt =
                engaged ? privateModeDuration().map { start.addingTimeInterval($0) } : nil
            stamped.privateModeSkippedCopies = 0
            return stamped
        }

        /// Internal so headless tests can drive the timer turn without waiting
        /// on a wall clock; production reaches it only through the timer.
        func refreshStatus() {
            expirePrivateModeIfDue()
            let current = monitor.status
            if status != current { status = current }
        }

        /// Applies the screen-share decision without touching pasteboard content.
        /// The monitor's next polling turn maps this flag to its public status.
        func refreshScreenSharePause() {
            let shouldPause = autoPauseOnScreenShare && screenShareIsActive()
            if monitor.pausedForScreenShare != shouldPause {
                monitor.pausedForScreenShare = shouldPause
            }
        }

        private func invalidateTimers() {
            statusTimer?.invalidate()
            statusTimer = nil
            screenShareTimer?.invalidate()
            screenShareTimer = nil
        }
    }
#endif

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
                monitor.preferences = preferences
                onPreferencesChanged(preferences)
            }
        }

        public var autoPauseOnScreenShare: Bool {
            didSet { onAutoPauseChanged(autoPauseOnScreenShare) }
        }

        @ObservationIgnored private let monitor: any CaptureMonitoring
        @ObservationIgnored private let screenShareIsActive: @MainActor () -> Bool
        @ObservationIgnored private let onPreferencesChanged:
            @MainActor (CapturePreferences) -> Void
        @ObservationIgnored private let onAutoPauseChanged: @MainActor (Bool) -> Void
        @ObservationIgnored private var statusTimer: Timer?
        @ObservationIgnored private var screenShareTimer: Timer?

        public init(
            monitor: any CaptureMonitoring,
            preferences: CapturePreferences,
            autoPauseOnScreenShare: Bool,
            screenShareIsActive: @escaping @MainActor () -> Bool,
            onPreferencesChanged: @escaping @MainActor (CapturePreferences) -> Void = { _ in },
            onAutoPauseChanged: @escaping @MainActor (Bool) -> Void = { _ in }
        ) {
            self.monitor = monitor
            self.preferences = preferences
            self.autoPauseOnScreenShare = autoPauseOnScreenShare
            self.screenShareIsActive = screenShareIsActive
            self.onPreferencesChanged = onPreferencesChanged
            self.onAutoPauseChanged = onAutoPauseChanged
            status = monitor.status
            monitor.preferences = preferences
        }

        /// Starts capture and the same lightweight status/screen-share timers
        /// formerly scheduled by `AppModel`. Screen-share detection intentionally
        /// waits for its first three-second tick, preserving launch timing.
        public func activate() {
            invalidateTimers()
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

        /// Internal so headless tests can drive the timer turn without waiting
        /// on a wall clock; production reaches it only through the timer.
        func refreshStatus() {
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

#if os(macOS)
    import ClipboardCore
    import Testing

    @testable import GanchoAppCore

    @MainActor
    private final class CaptureMonitorSpy: CaptureMonitoring {
        var preferences: CapturePreferences
        var status: MonitorStatus = .stopped
        var pausedForScreenShare = false
        private(set) var startCount = 0
        private(set) var stopCount = 0
        private(set) var ignoreCount = 0

        init(preferences: CapturePreferences = .init()) {
            self.preferences = preferences
        }

        func start() {
            startCount += 1
            status = .running
        }

        func stop() {
            stopCount += 1
            status = .stopped
        }

        func ignoreNextCopy() {
            ignoreCount += 1
        }
    }

    @MainActor
    private final class CaptureLifecycleRecorder {
        var savedPreferences: [CapturePreferences] = []
        var savedAutoPauseValues: [Bool] = []
        var screenShareIsActive = false
        var privateModeEngagedCount = 0
    }

    @Suite("Capture lifecycle controller — macOS monitor ownership")
    @MainActor
    struct CaptureLifecycleControllerTests {
        private func makeController(
            monitor: CaptureMonitorSpy,
            recorder: CaptureLifecycleRecorder = CaptureLifecycleRecorder(),
            autoPauseOnScreenShare: Bool = true
        ) -> CaptureLifecycleController {
            CaptureLifecycleController(
                monitor: monitor,
                preferences: monitor.preferences,
                autoPauseOnScreenShare: autoPauseOnScreenShare,
                screenShareIsActive: { recorder.screenShareIsActive },
                onPreferencesChanged: { recorder.savedPreferences.append($0) },
                onPrivateModeEngaged: { recorder.privateModeEngagedCount += 1 },
                onAutoPauseChanged: { recorder.savedAutoPauseValues.append($0) })
        }

        @Test("Activation starts capture and mirrors monitor status")
        func activationStartsAndMirrors() {
            let monitor = CaptureMonitorSpy()
            let controller = makeController(monitor: monitor)

            controller.activate()

            #expect(monitor.startCount == 1)
            #expect(controller.status == .running)
            controller.deactivate()
        }

        @Test("A status timer turn mirrors an external monitor transition")
        func statusRefreshMirrorsMonitor() {
            let monitor = CaptureMonitorSpy()
            let controller = makeController(monitor: monitor)
            monitor.status = .deniedByPrivacySettings

            controller.refreshStatus()

            #expect(controller.status == .deniedByPrivacySettings)
        }

        @Test("Capture toggle preserves start-stop behavior")
        func captureToggle() {
            let monitor = CaptureMonitorSpy()
            let controller = makeController(monitor: monitor)

            controller.toggleCapture()
            #expect(monitor.startCount == 1)
            #expect(controller.status == .running)

            controller.toggleCapture()
            #expect(monitor.stopCount == 1)
            #expect(controller.status == .stopped)
        }

        @Test("Preference changes update the monitor and persistence callback")
        func preferencesPropagate() {
            let monitor = CaptureMonitorSpy()
            let recorder = CaptureLifecycleRecorder()
            let controller = makeController(monitor: monitor, recorder: recorder)
            var updated = controller.preferences
            updated.captureImages = false

            controller.preferences = updated

            #expect(monitor.preferences == updated)
            #expect(recorder.savedPreferences == [updated])
        }

        @Test("Private mode is one coordinated preference mutation")
        func privateModeToggle() {
            let monitor = CaptureMonitorSpy()
            let recorder = CaptureLifecycleRecorder()
            let controller = makeController(monitor: monitor, recorder: recorder)

            controller.togglePrivateMode()

            #expect(controller.preferences.isPrivateModePaused)
            #expect(monitor.preferences.isPrivateModePaused)
            #expect(recorder.savedPreferences == [controller.preferences])
        }

        /// The teardown hung off this callback cancels in-flight OCR and
        /// dismisses whatever toast is on screen — including a "Clip deleted —
        /// Undo" toast and its only affordance. Hung off every preferences
        /// save instead of the transition, an unrelated Settings toggle would
        /// silently destroy it.
        @Test("Private mode engages once on the transition, never on later saves")
        func privateModeEngagesOnlyOnTheTransition() {
            let monitor = CaptureMonitorSpy()
            let recorder = CaptureLifecycleRecorder()
            let controller = makeController(monitor: monitor, recorder: recorder)

            // An unrelated toggle while Private Mode is off: nothing engages.
            var updated = controller.preferences
            updated.captureImages = false
            controller.preferences = updated
            #expect(recorder.privateModeEngagedCount == 0)

            controller.togglePrivateMode()
            #expect(recorder.privateModeEngagedCount == 1)

            // An unrelated toggle while Private Mode is already ON must not
            // re-engage, though it does still save.
            updated = controller.preferences
            updated.captureFileReferences = false
            controller.preferences = updated
            #expect(recorder.privateModeEngagedCount == 1)
            #expect(recorder.savedPreferences.count == 3)

            // Leaving and re-entering engages again, once.
            controller.togglePrivateMode()
            #expect(recorder.privateModeEngagedCount == 1)
            controller.togglePrivateMode()
            #expect(recorder.privateModeEngagedCount == 2)
        }

        @Test("Screen-share pause follows detection and the user opt-out")
        func screenSharePause() {
            let monitor = CaptureMonitorSpy()
            let recorder = CaptureLifecycleRecorder()
            recorder.screenShareIsActive = true
            let controller = makeController(monitor: monitor, recorder: recorder)

            controller.refreshScreenSharePause()
            #expect(monitor.pausedForScreenShare)

            controller.autoPauseOnScreenShare = false
            #expect(recorder.savedAutoPauseValues == [false])
            controller.refreshScreenSharePause()
            #expect(!monitor.pausedForScreenShare)
        }

        @Test("Ignore-next-copy delegates without reading content")
        func ignoreNextCopy() {
            let monitor = CaptureMonitorSpy()
            let controller = makeController(monitor: monitor)

            controller.ignoreNextCopy()

            #expect(monitor.ignoreCount == 1)
        }
    }
#endif

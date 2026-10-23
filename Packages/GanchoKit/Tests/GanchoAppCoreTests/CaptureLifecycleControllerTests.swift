#if os(macOS)
    import ClipboardCore
    import Foundation
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
        var now = Date(timeIntervalSince1970: 1_000_000)
        var privateModeDuration: TimeInterval? = 3_600
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
                onAutoPauseChanged: { recorder.savedAutoPauseValues.append($0) },
                now: { recorder.now },
                privateModeDuration: { recorder.privateModeDuration })
        }

        @Test("Turning Private Mode on stamps its start and deadline; off clears them")
        func privateModeStamps() {
            let monitor = CaptureMonitorSpy()
            let recorder = CaptureLifecycleRecorder()
            let controller = makeController(monitor: monitor, recorder: recorder)

            controller.togglePrivateMode()
            #expect(controller.preferences.privateModeStartedAt == recorder.now)
            #expect(
                controller.preferences.privateModeEndsAt
                    == recorder.now.addingTimeInterval(3_600))
            #expect(monitor.preferences == controller.preferences)
            #expect(recorder.savedPreferences.last == controller.preferences)

            controller.togglePrivateMode()
            #expect(controller.preferences.privateModeStartedAt == nil)
            #expect(controller.preferences.privateModeEndsAt == nil)
        }

        @Test("Until I turn it off leaves no deadline, so the timer never ends it")
        func privateModeWithoutDeadline() {
            let monitor = CaptureMonitorSpy()
            let recorder = CaptureLifecycleRecorder()
            recorder.privateModeDuration = nil
            let controller = makeController(monitor: monitor, recorder: recorder)

            controller.togglePrivateMode()
            #expect(controller.preferences.privateModeEndsAt == nil)
            recorder.now = recorder.now.addingTimeInterval(86_400 * 30)
            controller.refreshStatus()
            #expect(controller.preferences.isPrivateModePaused)
        }

        @Test("The status timer ends Private Mode at its deadline, not before")
        func privateModeAutoOff() {
            let monitor = CaptureMonitorSpy()
            let recorder = CaptureLifecycleRecorder()
            let controller = makeController(monitor: monitor, recorder: recorder)
            controller.togglePrivateMode()

            recorder.now = recorder.now.addingTimeInterval(3_599)
            controller.refreshStatus()
            #expect(controller.preferences.isPrivateModePaused)

            recorder.now = recorder.now.addingTimeInterval(1)
            controller.refreshStatus()
            #expect(!controller.preferences.isPrivateModePaused)
            #expect(!monitor.preferences.isPrivateModePaused)
            #expect(controller.preferences.privateModeEndsAt == nil)
        }

        @Test("A new auto-off choice moves the current deadline from its start")
        func privateModeDurationChangeAppliesNow() {
            let monitor = CaptureMonitorSpy()
            let recorder = CaptureLifecycleRecorder()
            recorder.privateModeDuration = nil
            let controller = makeController(monitor: monitor, recorder: recorder)
            controller.togglePrivateMode()
            let start = recorder.now
            #expect(controller.preferences.privateModeEndsAt == nil)

            recorder.now = start.addingTimeInterval(600)
            recorder.privateModeDuration = 900
            controller.privateModeDurationChanged()
            #expect(controller.preferences.privateModeEndsAt == start.addingTimeInterval(900))
            #expect(controller.preferences.isPrivateModePaused)

            recorder.privateModeDuration = 300
            controller.privateModeDurationChanged()
            #expect(!controller.preferences.isPrivateModePaused, "a deadline already past ends it")

            controller.privateModeDurationChanged()
            #expect(!controller.preferences.isPrivateModePaused, "off stays off")
        }

        @Test(
            "A deadline that passed while the app was closed ends Private Mode before capture starts"
        )
        func privateModeDeadlineSurvivesRelaunch() {
            let recorder = CaptureLifecycleRecorder()
            let stored = CapturePreferences(
                isPrivateModePaused: true,
                privateModeStartedAt: recorder.now.addingTimeInterval(-7_200),
                privateModeEndsAt: recorder.now.addingTimeInterval(-3_600))
            let monitor = CaptureMonitorSpy(preferences: stored)
            let controller = makeController(monitor: monitor, recorder: recorder)
            #expect(controller.preferences.isPrivateModePaused, "loading alone changes nothing")

            controller.activate()
            #expect(!controller.preferences.isPrivateModePaused)
            #expect(!monitor.preferences.isPrivateModePaused)
            controller.deactivate()
        }

        @Test("Copies are counted only while Private Mode is on, and reset on the next one")
        func privateModeCopyCount() {
            let monitor = CaptureMonitorSpy()
            let recorder = CaptureLifecycleRecorder()
            let controller = makeController(monitor: monitor, recorder: recorder)

            controller.notePrivateModeCopy()
            #expect(controller.preferences.privateModeSkippedCopies == 0)

            controller.togglePrivateMode()
            controller.notePrivateModeCopy()
            controller.notePrivateModeCopy()
            #expect(controller.preferences.privateModeSkippedCopies == 2)

            controller.togglePrivateMode()
            controller.togglePrivateMode()
            #expect(controller.preferences.privateModeSkippedCopies == 0)
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

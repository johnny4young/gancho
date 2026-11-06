#if os(macOS)
    import ClipboardCore
    import Foundation
    import Testing

    @testable import GanchoAppCore

    @MainActor
    private final class CaptureMonitorSpy: CaptureMonitoring {
        var preferences: CapturePreferences
        var status: MonitorStatus = .stopped {
            didSet { if status != oldValue { onStateChange?() } }
        }
        var pausedForScreenShare = false
        var isIgnoringNextCopy = false {
            didSet { if isIgnoringNextCopy != oldValue { onStateChange?() } }
        }
        var onStateChange: (() -> Void)?
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
            isIgnoringNextCopy = true
        }
    }

    @MainActor
    private final class CaptureLifecycleRecorder {
        var savedPreferences: [CapturePreferences] = []
        var savedAutoPauseValues: [Bool] = []
        var sharingApp: String?
        var privateModeEngagedCount = 0
        var now = Date(timeIntervalSince1970: 1_000_000)
        var privateModeDuration: TimeInterval? = 3_600
        /// The running-app observer the controller registered, if it holds one.
        var runningApplicationsChanged: (@MainActor @Sendable () -> Void)?
        weak var runningApplicationsToken: NSObject?
    }

    @Suite("Capture lifecycle controller — macOS monitor ownership")
    @MainActor
    struct CaptureLifecycleControllerTests {
        private func makeController(
            monitor: CaptureMonitorSpy,
            recorder: CaptureLifecycleRecorder = CaptureLifecycleRecorder(),
            autoPauseOnScreenShare: Bool = true,
            now: (@MainActor () -> Date)? = nil,
            firstScreenShareCheckDelay: Duration = .seconds(3),
            screenShareRecheckDelays: [Duration] = [.seconds(1), .seconds(2)]
        ) -> CaptureLifecycleController {
            CaptureLifecycleController(
                monitor: monitor,
                preferences: monitor.preferences,
                autoPauseOnScreenShare: autoPauseOnScreenShare,
                screenShareApp: { recorder.sharingApp },
                onPreferencesChanged: { recorder.savedPreferences.append($0) },
                onPrivateModeEngaged: { recorder.privateModeEngagedCount += 1 },
                onAutoPauseChanged: { recorder.savedAutoPauseValues.append($0) },
                now: now ?? { recorder.now },
                privateModeDuration: { recorder.privateModeDuration },
                observeRunningApplications: { handler in
                    let token = NSObject()
                    recorder.runningApplicationsChanged = handler
                    recorder.runningApplicationsToken = token
                    return token
                },
                firstScreenShareCheckDelay: firstScreenShareCheckDelay,
                screenShareRecheckDelays: screenShareRecheckDelays)
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
            controller.expirePrivateModeIfDue()
            #expect(controller.preferences.isPrivateModePaused)
        }

        @Test("Private Mode ends at its deadline, not before")
        func privateModeAutoOff() {
            let monitor = CaptureMonitorSpy()
            let recorder = CaptureLifecycleRecorder()
            let controller = makeController(monitor: monitor, recorder: recorder)
            controller.togglePrivateMode()

            recorder.now = recorder.now.addingTimeInterval(3_599)
            controller.expirePrivateModeIfDue()
            #expect(controller.preferences.isPrivateModePaused)

            recorder.now = recorder.now.addingTimeInterval(1)
            controller.expirePrivateModeIfDue()
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

        @Test("A monitor transition reaches the controller as it happens")
        func statusMirrorsMonitorTransitions() {
            let monitor = CaptureMonitorSpy()
            let controller = makeController(monitor: monitor)

            monitor.status = .deniedByPrivacySettings
            #expect(controller.status == .deniedByPrivacySettings)
            monitor.status = .pausedByScreenLock
            #expect(controller.status == .pausedByScreenLock)
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
            recorder.sharingApp = "Zoom"
            let controller = makeController(monitor: monitor, recorder: recorder)

            controller.refreshScreenSharePause()
            #expect(monitor.pausedForScreenShare)
            #expect(controller.sharingAppName == "Zoom")

            controller.autoPauseOnScreenShare = false
            #expect(recorder.savedAutoPauseValues == [false])
            controller.refreshScreenSharePause()
            #expect(!monitor.pausedForScreenShare)
            #expect(controller.sharingAppName == nil, "no pause, no sharing app to name")

            controller.autoPauseOnScreenShare = true
            controller.refreshScreenSharePause()
            controller.refreshScreenSharePause()
            #expect(controller.screenShareSession == 2, "a new share, not a repeated tick")
        }

        @Test("Ignore-next-copy delegates without reading content")
        func ignoreNextCopy() {
            let monitor = CaptureMonitorSpy()
            let controller = makeController(monitor: monitor)

            controller.ignoreNextCopy()

            #expect(monitor.ignoreCount == 1)
            #expect(controller.ignoresNextCopy, "the menu-bar badge shows the armed skip")
            monitor.isIgnoringNextCopy = false
            #expect(!controller.ignoresNextCopy, "a consumed skip clears as it is consumed")
        }

        @Test("A running-app change pauses capture for a share and resumes when it ends")
        func runningAppChangesDriveTheSharePause() {
            let monitor = CaptureMonitorSpy()
            let recorder = CaptureLifecycleRecorder()
            let controller = makeController(monitor: monitor, recorder: recorder)
            controller.activate()
            defer { controller.deactivate() }

            recorder.sharingApp = "Zoom"
            recorder.runningApplicationsChanged?()
            #expect(monitor.pausedForScreenShare)
            #expect(controller.sharingAppName == "Zoom")

            recorder.sharingApp = nil
            recorder.runningApplicationsChanged?()
            #expect(!monitor.pausedForScreenShare)
            #expect(controller.sharingAppName == nil)
        }

        @Test("A share helper named a moment after its launch is still caught")
        func lateNamedHelperIsCaught() async throws {
            let monitor = CaptureMonitorSpy()
            let recorder = CaptureLifecycleRecorder()
            let controller = makeController(
                monitor: monitor, recorder: recorder, firstScreenShareCheckDelay: .seconds(60),
                screenShareRecheckDelays: [.milliseconds(20), .milliseconds(20)])
            controller.activate()
            defer { controller.deactivate() }

            recorder.runningApplicationsChanged?()
            #expect(!monitor.pausedForScreenShare)
            recorder.sharingApp = "Zoom"
            for _ in 0..<250 where !monitor.pausedForScreenShare {
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(monitor.pausedForScreenShare, "no app changed again, yet the share is caught")
        }

        @Test("A share already running at launch is caught after the launch delay")
        func shareRunningAtLaunchIsCaught() async throws {
            let monitor = CaptureMonitorSpy()
            let recorder = CaptureLifecycleRecorder()
            recorder.sharingApp = "Zoom"
            let controller = makeController(
                monitor: monitor, recorder: recorder,
                firstScreenShareCheckDelay: .milliseconds(50))
            controller.activate()
            defer { controller.deactivate() }
            #expect(!monitor.pausedForScreenShare, "launch timing is preserved")

            for _ in 0..<250 where !monitor.pausedForScreenShare {
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(monitor.pausedForScreenShare)
            #expect(controller.sharingAppName == "Zoom")
        }

        @Test("Turning auto-pause on or off applies at once while capture is active")
        func autoPauseToggleAppliesAtOnce() {
            let monitor = CaptureMonitorSpy()
            let recorder = CaptureLifecycleRecorder()
            let controller = makeController(
                monitor: monitor, recorder: recorder, autoPauseOnScreenShare: false)
            controller.activate()
            defer { controller.deactivate() }
            recorder.sharingApp = "Zoom"

            controller.autoPauseOnScreenShare = true
            #expect(monitor.pausedForScreenShare)
            controller.autoPauseOnScreenShare = false
            #expect(!monitor.pausedForScreenShare)
        }

        @Test("Private Mode ends on its wall-clock deadline with no other event")
        func privateModeDeadlineFiresOnItsOwn() async throws {
            let monitor = CaptureMonitorSpy()
            let recorder = CaptureLifecycleRecorder()
            recorder.privateModeDuration = 0.2
            let controller = makeController(monitor: monitor, recorder: recorder, now: { Date() })
            controller.activate()
            defer { controller.deactivate() }
            controller.togglePrivateMode()
            #expect(controller.preferences.isPrivateModePaused)

            for _ in 0..<250 where controller.preferences.isPrivateModePaused {
                try await Task.sleep(for: .milliseconds(20))
            }
            #expect(!controller.preferences.isPrivateModePaused)
            #expect(!monitor.preferences.isPrivateModePaused)
        }

        @Test("Deactivating stops following running apps, including a change already in flight")
        func deactivationReleasesTheObserver() {
            let monitor = CaptureMonitorSpy()
            let recorder = CaptureLifecycleRecorder()
            let controller = makeController(monitor: monitor, recorder: recorder)

            controller.activate()
            #expect(recorder.runningApplicationsToken != nil)
            controller.deactivate()
            #expect(recorder.runningApplicationsToken == nil)

            recorder.sharingApp = "Zoom"
            recorder.runningApplicationsChanged?()
            #expect(!monitor.pausedForScreenShare)
        }
    }
#endif

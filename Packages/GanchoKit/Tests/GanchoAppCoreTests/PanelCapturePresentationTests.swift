import Testing

@testable import GanchoAppCore

@Suite("Panel capture presentation policy")
struct PanelCapturePresentationTests {
    @Test("Ephemeral storage outranks every operational interruption")
    func ephemeralStoragePrecedence() {
        let presentation = PanelCapturePresentation.resolve(
            storageIsEphemeral: true,
            privateModeEnabled: true,
            runtimeStatus: .deniedByPrivacySettings)

        #expect(presentation.notice == .storageEphemeral)
        #expect(!presentation.isCapturing)
    }

    @Test("The signed evidence fixture can suppress only its expected storage warning")
    func evidenceFixtureSuppression() {
        let presentation = PanelCapturePresentation.resolve(
            storageIsEphemeral: true,
            suppressExpectedEphemeralNotice: true,
            privateModeEnabled: false,
            runtimeStatus: .deniedByPrivacySettings)

        #expect(presentation.notice == .denied)
    }

    @Test("Ephemeral storage does not imply that capture itself is paused")
    func ephemeralStorageKeepsActiveIndicator() {
        let presentation = PanelCapturePresentation.resolve(
            storageIsEphemeral: true,
            privateModeEnabled: false,
            runtimeStatus: .running)

        #expect(presentation.notice == .storageEphemeral)
        #expect(presentation.isCapturing)
    }

    @Test(
        "Operational precedence remains permission, private mode, screen share, then stopped",
        arguments: [
            (PanelCaptureRuntimeStatus.deniedByPrivacySettings, true, PanelCaptureNotice.denied),
            (PanelCaptureRuntimeStatus.pausedByScreenShare, true, .privateMode),
            (PanelCaptureRuntimeStatus.pausedByScreenShare, false, .screenShare),
            (PanelCaptureRuntimeStatus.stopped, false, .paused)
        ])
    func operationalPrecedence(
        runtimeStatus: PanelCaptureRuntimeStatus,
        privateModeEnabled: Bool,
        expectedNotice: PanelCaptureNotice
    ) {
        let presentation = PanelCapturePresentation.resolve(
            storageIsEphemeral: false,
            privateModeEnabled: privateModeEnabled,
            runtimeStatus: runtimeStatus)

        #expect(presentation.notice == expectedNotice)
        #expect(!presentation.isCapturing)
    }

    @Test(
        "User and screen-lock pauses do not invent a panel notice",
        arguments: [
            PanelCaptureRuntimeStatus.pausedByUser,
            .pausedByScreenLock
        ])
    func silentPauseStates(runtimeStatus: PanelCaptureRuntimeStatus) {
        let presentation = PanelCapturePresentation.resolve(
            storageIsEphemeral: false,
            privateModeEnabled: false,
            runtimeStatus: runtimeStatus)

        #expect(presentation.notice == nil)
        #expect(!presentation.isCapturing)
    }

    @Test(
        "Only an active unpaused monitor reports capture",
        arguments: [
            (PanelCaptureRuntimeStatus.running, false, true),
            (.running, true, false),
            (.pausedByUser, false, false),
            (.pausedByScreenLock, false, false),
            (.pausedByScreenShare, false, false),
            (.deniedByPrivacySettings, false, false),
            (.stopped, false, false)
        ])
    func captureIndicator(
        runtimeStatus: PanelCaptureRuntimeStatus,
        privateModeEnabled: Bool,
        expected: Bool
    ) {
        let presentation = PanelCapturePresentation.resolve(
            storageIsEphemeral: false,
            privateModeEnabled: privateModeEnabled,
            runtimeStatus: runtimeStatus)

        #expect(presentation.isCapturing == expected)
    }

    @Test("Notices expose only the actions the shell can perform")
    func noticeActions() {
        #expect(PanelCaptureNotice.privateMode.action == .resumePrivateMode)
        #expect(PanelCaptureNotice.paused.action == .resumeCapture)
        #expect(PanelCaptureNotice.denied.action == .openPermissionSettings)
        #expect(PanelCaptureNotice.storageEphemeral.action == nil)
        #expect(PanelCaptureNotice.screenShare.action == nil)
    }
}

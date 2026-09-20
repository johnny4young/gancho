import AppKit
import GanchoAI
import GanchoAppCore

extension AppModel {
    /// Whether "Copy text from screen" can do anything right now. The menu
    /// renders from this predicate, the way `canCopyImageText` already gates
    /// the image command: an enabled item that returns silently is worse than
    /// a disabled one. The shortcut and the helper's menu cannot read it, so
    /// `copyScreenText` still explains the refusal instead of returning mute.
    var canCopyScreenText: Bool { !preferences.isPrivateModePaused }

    func copyScreenText() {
        guard canCopyScreenText else {
            toasts.show(
                GanchoToast(
                    message: "Private Mode is on. Turn it off to copy text from the screen.",
                    style: .warning))
            return
        }
        #if DEBUG
            // UI-test launch presentation only. Kept out of release builds the
            // way every other `-*-for-ui-test` hook in this target is: the
            // readers live behind `-open-panel-on-launch`, so writing it on a
            // real invocation threads a test concern through the feature path.
            uiTestLaunchPresentationIsSuppressed = true
        #endif
        // Not redundant with `begin()`'s own cancel below: the authorization
        // check between here and there can put a modal alert on screen, and a
        // selector overlay from a previous request would sit above it.
        screenTextWorkflow.cancel()
        manualOCRWindow.close()
        manualOCR.cancel()
        toasts.dismiss()
        let previousApp = NSWorkspace.shared.frontmostApplication
        let authorization = screenCaptureAuthorization()
        guard authorization == .allowed else {
            previousApp?.activate()
            guard authorization == .denied else { return }
            toasts.show(
                GanchoToast(
                    message:
                        "Allow Screen Recording in System Settings to copy text from the screen.",
                    style: .warning,
                    action: ToastAction(title: "Open Settings") {
                        guard
                            let url = URL(
                                string:
                                    "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
                            )
                        else { return }
                        NSWorkspace.shared.open(url)
                    }))
            return
        }
        let workflow = screenTextWorkflow
        let request = workflow.begin(previousApp: previousApp)
        let detector = SensitiveDataDetector()
        manualOCR.start(
            recognize: {
                #if DEBUG
                    // Exercise result delivery without reading any screen pixels.
                    if ScreenTextCapture.hasSensitiveResultFixture {
                        return ManualOCRResult(text: "card 4242 4242 4242 4242")
                    }
                #endif
                return try await workflow.recognize(
                    request,
                    isAllowed: { [weak self] in self?.preferences.isPrivateModePaused == false },
                    didCapture: { [weak self] in self?.showManualOCRProgress() })
            },
            isAllowed: { [weak self] in
                await MainActor.run { self?.preferences.isPrivateModePaused == false }
            },
            isSensitive: { detector.detect($0) != nil },
            clipboardRevision: { NSPasteboard.general.changeCount },
            copy: { [weak self] in self?.writeManualText($0) },
            didFinish: { [weak self] state in
                // Reached before `recognize` runs when the session's own
                // eligibility check refuses (`.unavailable`), so this really is
                // the teardown for a selector that was begun and never shown.
                workflow.cancel()
                self?.finishScreenText(state)
            })
    }

    /// Screen OCR has no clip and no saved image, so the states whose copy
    /// speaks about one need their own wording — `.failed` is not the only one
    /// that would otherwise describe something the user never had.
    private func finishScreenText(_ state: ManualOCRSession.State) {
        switch state {
        case .failed:
            let message: LocalizedStringResource =
                CGPreflightScreenCaptureAccess()
                ? "Couldn’t read this screen region. Try selecting it again."
                : "Screen capture permission changed. Check Screen Recording in System Settings and retry."
            toasts.show(GanchoToast(message: message, style: .warning))
        case .unavailable:
            toasts.show(
                GanchoToast(
                    message: "That screen region is no longer available. Select it again.",
                    style: .warning))
        case .copied, .ready, .noText, .idle, .recognizing:
            finishManualOCR(state, surface: .detached)
        }
    }

    private func screenCaptureAuthorization() -> ScreenTextAuthorization {
        #if DEBUG
            if ScreenTextCapture.hasSensitiveResultFixture { return .allowed }
            if ScreenTextCapture.isSelectionOnlyTest { return .allowed }
            if CommandLine.arguments.contains("-screen-ocr-denied-for-ui-test") { return .denied }
            if CommandLine.arguments.contains("-screen-ocr-purpose-for-ui-test") {
                return ScreenTextAuthorization.resolve(
                    isAuthorized: { false }, confirmPurpose: confirmScreenCapturePurpose,
                    requestAccess: { false })
            }
        #endif
        return ScreenTextAuthorization.resolve(
            isAuthorized: { CGPreflightScreenCaptureAccess() },
            confirmPurpose: confirmScreenCapturePurpose,
            requestAccess: { CGRequestScreenCaptureAccess() })
    }

    private func confirmScreenCapturePurpose() -> Bool {
        let alert = NSAlert()
        alert.messageText = String(localized: "Copy screen text privately")
        alert.informativeText = String(
            localized:
                "Allow region capture. OCR stays on this Mac; nothing is saved automatically."
        )
        alert.addButton(withTitle: String(localized: "Continue"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        // Gancho is a menu-bar agent with no Dock tile, and this path runs
        // while another app is frontmost. Without activating first, a modal
        // alert can open BEHIND that app: the main run loop is wedged in
        // `runModal` and the user has nothing to click and no icon to find.
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }
}

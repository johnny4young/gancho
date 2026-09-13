import AppKit
import GanchoAppCore

extension AppModel {
    func copyScreenText() {
        guard !preferences.isPrivateModePaused else { return }
        uiTestLaunchPresentationIsSuppressed = true
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
        manualOCR.start(
            recognize: { [weak self] in
                try await workflow.recognize(request) { [weak self] in
                    self?.toasts.show(
                        GanchoToast(
                            message: "Recognizing text…", style: .pending,
                            action: ToastAction(
                                title: "Cancel", accessibilityIdentifier: "ocr-cancel"
                            ) { [weak self] in
                                self?.manualOCR.cancel()
                                self?.toasts.dismiss()
                            }))
                }
            },
            isAllowed: { [weak self] in
                await MainActor.run { self?.preferences.isPrivateModePaused == false }
            },
            clipboardRevision: { NSPasteboard.general.changeCount },
            copy: { [weak self] in self?.writeManualText($0) },
            didFinish: { [weak self] state in
                workflow.cancel()
                self?.finishScreenText(state)
            })
    }
    private func finishScreenText(_ state: ManualOCRSession.State) {
        if state == .failed {
            let message: LocalizedStringResource =
                CGPreflightScreenCaptureAccess()
                ? "Couldn’t read this screen region. Try selecting it again."
                : "Screen capture permission changed. Check Screen Recording in System Settings and retry."
            toasts.show(GanchoToast(message: message, style: .warning))
        } else {
            finishManualOCR(state)
        }
    }

    private func screenCaptureAuthorization() -> ScreenTextAuthorization {
        #if DEBUG
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
        return alert.runModal() == .alertFirstButtonReturn
    }

}

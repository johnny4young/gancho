import AppKit
import ClipboardCore
import GanchoAppCore
import GanchoKit

extension AppModel {
    func canCopyImageText(_ item: ClipItem) -> Bool {
        item.kind == .image && !ClipSafePresentation.requiresMasking(item)
            && !preferences.isPrivateModePaused && !pendingDeletionIDs.contains(item.id)
            && (item.expiresAt.map { $0 > .now } ?? true)
    }

    func copyImageText(_ item: ClipItem) {
        guard canCopyImageText(item), let reader = store as? any ImageTextReading else { return }
        manualOCRWindow.close()
        manualOCR.start(
            recognize: { try await ManualImageTextService().text(for: item.id, store: reader) },
            isAllowed: { [weak self] in
                guard (try? await reader.permitsImageText(id: item.id, now: .now)) == true else {
                    return false
                }
                return await MainActor.run {
                    guard let self else { return false }
                    return self.canCopyImageText(item)
                }
            },
            clipboardRevision: { NSPasteboard.general.changeCount },
            copy: { [weak self] in self?.writeManualText($0) },
            didFinish: { [weak self] state in self?.finishManualOCR(state) })
        toasts.show(
            GanchoToast(
                message: "Recognizing text…", style: .pending,
                action: ToastAction(title: "Cancel", accessibilityIdentifier: "ocr-cancel") {
                    [weak self] in
                    self?.manualOCR.cancel()
                    self?.toasts.dismiss()
                }))
    }

    func cancelManualOCRIfRecognizing() {
        guard manualOCR.state == .recognizing else { return }
        manualOCR.cancel()
        toasts.dismiss()
    }

    func writeManualText(_ text: String) {
        #if DEBUG
            // UI automation must never replace the user's clipboard.
            if CommandLine.arguments.contains("-ui-test-paste-sink") { return }
        #endif
        SystemPasteboardWriter().write(.text(text), asPlainText: true)
    }

    private func finishManualOCR(_ state: ManualOCRSession.State) {
        switch state {
        case .copied, .ready:
            toasts.show(
                GanchoToast(
                    message: state == .copied ? "Text copied" : "Text ready — clipboard unchanged",
                    action: ToastAction(title: "Review", accessibilityIdentifier: "ocr-review") {
                        [weak self] in
                        guard let self else { return }
                        self.toasts.dismiss()
                        self.manualOCRWindow.show(model: self)
                    }))
            let request = manualOCR.requestID
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(6))
                guard let self, self.manualOCR.requestID == request,
                    !self.manualOCRWindow.isVisible
                else { return }
                self.manualOCR.cancel()
            }
        case .noText:
            toasts.show(GanchoToast(message: "No readable text found", style: .warning))
        case .unavailable:
            toasts.show(
                GanchoToast(message: "Image is no longer available for OCR", style: .warning))
        case .failed:
            toasts.show(
                GanchoToast(
                    message: "Couldn’t read this image. Try another image.", style: .warning))
        case .idle, .recognizing: break
        }
    }

    func saveManualText(_ text: String) async -> Bool {
        guard !preferences.isPrivateModePaused else { return false }
        do {
            _ = try await ClipIngestionCoordinator().ingest(
                PasteboardCapture(text: text),
                configuration: .init(
                    sensitiveLifetime: retentionPolicy.sensitiveLifetime,
                    detectSecrets: true, tier: tier, intelligence: intelligence),
                store: store, syncEngine: syncController.engine)
            await refreshRecents()
            return true
        } catch { return false }
    }
}

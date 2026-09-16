import AppKit
import ClipboardCore
import GanchoAppCore
import GanchoKit

extension AppModel {
    /// How long a finished result stays reachable. The result toast carries the
    /// only way to reopen it, so this is ALSO the toast's duration: the two must
    /// be one number, or the text outlives its affordance (unreachable) or dies
    /// while the button is still on screen (a click that silently does nothing).
    private static let manualOCRReviewWindow: Duration = .seconds(12)

    /// Upper bound for the "Recognizing text…" toast. Recognition can outrun the
    /// default actionable-toast life, and the toast carries the only Cancel, so
    /// it stays until a terminal state replaces or dismisses it.
    private static let manualOCRRecognizingToastLifetime: Duration = .seconds(120)

    func canCopyImageText(_ item: ClipItem) -> Bool {
        // The reader check belongs HERE, not only in `copyImageText`: every call
        // site renders the menu item from this predicate, and an in-memory store
        // (a failed durable open) conforms to no reader — offering an action that
        // returns silently is worse than not offering it.
        store is any ImageTextReading && item.kind == .image
            && !ClipSafePresentation.requiresMasking(item)
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
                }),
            duration: Self.manualOCRRecognizingToastLifetime)
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
                    }),
                duration: Self.manualOCRReviewWindow)
            let request = manualOCR.requestID
            Task { [weak self] in
                // Same window as the toast above, plus a beat so the result can
                // never expire while its only button is still clickable.
                try? await Task.sleep(for: Self.manualOCRReviewWindow + .seconds(1))
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

import AppKit
import ClipboardCore
import GanchoAI
import GanchoAppCore
import GanchoKit

extension AppModel {
    /// Where an OCR request shows its progress and result.
    enum ManualOCRSurface {
        /// The history panel's peek: the "Text in image" section renders every
        /// state in place, so no toast and no auto-discard — the result lives
        /// exactly as long as the clip stays selected.
        case peek
        /// Any other entry point (Library, large preview): toasts plus the
        /// review window, because there is no pane to render into.
        case detached
    }

    /// How long a detached result stays reachable. The result toast carries the
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

    func copyImageText(_ item: ClipItem, surface: ManualOCRSurface = .detached) {
        guard canCopyImageText(item), let reader = store as? any ImageTextReading else { return }
        manualOCRWindow.close()
        let detector = SensitiveDataDetector()
        manualOCR.start(
            itemID: item.id,
            recognize: { try await ManualImageTextService().result(for: item.id, store: reader) },
            isAllowed: { [weak self] in
                guard (try? await reader.permitsImageText(id: item.id, now: .now)) == true else {
                    return false
                }
                return await MainActor.run {
                    guard let self else { return false }
                    return self.canCopyImageText(item)
                }
            },
            isSensitive: { detector.detect($0) != nil },
            clipboardRevision: { NSPasteboard.general.changeCount },
            copy: { [weak self] in self?.writeManualText($0) },
            didFinish: { [weak self] state in self?.finishManualOCR(state, surface: surface) })
        guard surface == .detached else { return }
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

    /// Copies one recognized line, or an edited draft, after the same
    /// revalidation the review window applies: the source must still permit it.
    @discardableResult
    func copyManualText(_ text: String) async -> Bool {
        guard let validated = await manualOCR.reviewedText(text) else { return false }
        writeManualText(validated)
        return true
    }

    private func finishManualOCR(_ state: ManualOCRSession.State, surface: ManualOCRSurface) {
        switch surface {
        case .peek:
            // The section shows the state; sighted users need no toast. The
            // section is not focused, so VoiceOver still gets one announcement.
            announceManualOCR(state)
        case .detached:
            showDetachedManualOCRToast(state)
        }
    }

    private func announceManualOCR(_ state: ManualOCRSession.State) {
        let message: String? =
            switch state {
            case .copied: String(localized: "Text copied")
            case .ready:
                if manualOCR.isSensitive {
                    String(localized: "Text contains a secret — review before copying")
                } else {
                    String(localized: "Text ready — clipboard unchanged")
                }
            case .noText: String(localized: "No readable text found")
            case .unavailable: String(localized: "Image is no longer available for OCR")
            case .failed: String(localized: "Couldn’t read this image. Try another image.")
            case .idle, .recognizing: nil
            }
        guard let message else { return }
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.high.rawValue
            ])
    }

    private func showDetachedManualOCRToast(_ state: ManualOCRSession.State) {
        switch state {
        case .copied, .ready:
            let message: LocalizedStringResource =
                if state == .copied {
                    "Text copied"
                } else if manualOCR.isSensitive {
                    "Text contains a secret — review before copying"
                } else {
                    "Text ready — clipboard unchanged"
                }
            toasts.show(
                GanchoToast(
                    message: message,
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

    /// Opens a link or mailto found in recognized text. It takes the entity,
    /// not a URL: `ImageTextEntityDetector` is the only way to make one, so its
    /// allowlist (http, https, mailto with a host) is the single gate and an
    /// unvetted URL cannot reach this call. A launch the system refuses (no
    /// mail client, no browser) is reported, never a dead click.
    func openRecognizedEntity(_ entity: ImageTextEntity) {
        #if DEBUG
            // UI automation must never open a browser or a mail client on the
            // runner; the paste sink marks that launch too (see
            // `makePasteBackService`).
            if CommandLine.arguments.contains("-ui-test-paste-sink") { return }
        #endif
        if !NSWorkspace.shared.open(entity.url) {
            toasts.show(GanchoToast(message: "Couldn’t open that link.", style: .warning))
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

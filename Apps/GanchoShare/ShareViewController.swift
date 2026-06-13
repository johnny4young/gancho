import ClipboardCore
import GanchoAI
import GanchoKit
import Social
import UIKit
import UniformTypeIdentifiers

/// Minimal share-sheet entry point: extract text/URL/image attachments,
/// drop them in the App Group inbox, dismiss. No UI of its own beyond the
/// system sheet — capture should feel like a single tap.
///
/// Extensions live for seconds and must never own the store; the inbox file
/// handoff keeps GRDB single-owner in the host app (see `SharedInbox`).
final class ShareViewController: UIViewController {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        Task {
            await ingestAttachments()
            extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func ingestAttachments() async {
        guard let inbox = SharedInbox.inAppGroup() else { return }
        let providers = (extensionContext?.inputItems ?? [])
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] }

        // Tier-0 classification runs HERE: deterministic, <5ms, no model
        // loads — comfortably inside the extension memory ceiling. Large
        // payloads aren't a problem either: the deposit IS the deferred
        // import (a file the app processes later).
        let classifier = RuleClassifier()
        for provider in providers {
            if let capture = await capture(from: provider) {
                let kind: ClipContentKind? =
                    switch capture.payload {
                    case .image: .image
                    default: capture.textRepresentation.map(classifier.classify)
                    }
                try? inbox.deposit(SharedInbox.PreparedCapture(capture: capture, kind: kind))
            }
        }
    }

    /// Richest-first extraction, mirroring the macOS reader's fidelity
    /// order: image > URL > plain text.
    private func capture(from provider: NSItemProvider) async -> PasteboardCapture? {
        if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
            let image = try? await provider.loadItem(forTypeIdentifier: UTType.image.identifier)
        {
            if let png = (image as? UIImage)?.pngData() {
                return PasteboardCapture(payload: .image(data: png, typeIdentifier: "public.png"))
            }
            if let url = image as? URL, let data = try? Data(contentsOf: url) {
                return PasteboardCapture(
                    payload: .image(data: data, typeIdentifier: UTType.image.identifier))
            }
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
            let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier)
                as? URL
        {
            return PasteboardCapture(text: url.absoluteString)
        }
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
            let item = try? await provider.loadItem(
                forTypeIdentifier: UTType.plainText.identifier)
        {
            if let text = item as? String, !text.isEmpty {
                return PasteboardCapture(text: text)
            }
            if let data = item as? Data, let text = String(data: data, encoding: .utf8),
                !text.isEmpty
            {
                return PasteboardCapture(text: text)
            }
        }
        return nil
    }
}

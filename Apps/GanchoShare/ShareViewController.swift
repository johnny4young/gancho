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
            let saved = await ingestAttachments()
            // The sheet otherwise vanishes with zero feedback; a success tap
            // confirms the capture actually landed, and an error tap says the
            // share did NOT save rather than letting it look like it did.
            let generator = UINotificationFeedbackGenerator()
            // Nonpositive is a failure, not a neutral outcome: nil means the
            // inbox could not be reached sealed, and zero means every
            // attachment was unsupported, unreadable, or failed to write. The
            // old `default: break` dismissed those two silently, which is the
            // one thing this feedback exists to prevent — the sheet vanishing
            // as though the share had saved.
            generator.notificationOccurred((saved ?? 0) > 0 ? .success : .error)
            extensionContext?.completeRequest(returningItems: nil)
        }
    }

    /// Deposits every attachment, or nil when the inbox cannot be reached
    /// sealed.
    ///
    /// Fail closed: without the content key a deposit would leave plaintext
    /// clipboard content sitting in the App Group container until the app's
    /// next launch, which is exactly the exposure the seal exists to prevent.
    /// Losing one share is recoverable — the user shares again; leaking it is
    /// not.
    private func ingestAttachments() async -> Int? {
        guard
            let key = try? StoreContentKey.load(
                keychainAccessGroup: KeychainPassphraseStore.iosSharedAccessGroup),
            let inbox = SharedInbox.inAppGroup(key: key)
        else { return nil }
        let providers = (extensionContext?.inputItems ?? [])
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] }

        // Tier-0 classification runs HERE: deterministic, <5ms, no model
        // loads — comfortably inside the extension memory ceiling. Large
        // payloads aren't a problem either: the deposit IS the deferred
        // import (a file the app processes later).
        let classifier = RuleClassifier()
        var saved = 0
        for provider in providers {
            if let capture = await capture(from: provider) {
                let kind: ClipContentKind? =
                    switch capture.payload {
                    case .image: .image
                    default: capture.textRepresentation.map(classifier.classify)
                    }
                if (try? inbox.deposit(
                    SharedInbox.PreparedCapture(capture: capture, kind: kind))) != nil
                {
                    saved += 1
                }
            }
        }
        return saved
    }

    /// Richest-first extraction, mirroring the macOS reader's fidelity
    /// order: image > URL > plain text.
    private func capture(from provider: NSItemProvider) async -> PasteboardCapture? {
        if let image = await imageCapture(from: provider) {
            return image
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

    /// The original image bytes under their own type (a JPEG stays a JPEG),
    /// whether the provider vends data or a file. Re-encoding to PNG is the
    /// last resort, for providers that only hand over a `UIImage`.
    private func imageCapture(from provider: NSItemProvider) async -> PasteboardCapture? {
        guard
            let type = provider.registeredContentTypes.first(where: { $0.conforms(to: .image) })
        else { return nil }
        var original = await loadData(type, from: provider)
        if original == nil { original = await loadFile(type, from: provider) }
        if let data = original {
            return PasteboardCapture(payload: .image(data: data, typeIdentifier: type.identifier))
        }
        let item = try? await provider.loadItem(forTypeIdentifier: UTType.image.identifier)
        if let url = item as? URL, let data = try? Data(contentsOf: url) {
            let fileType = UTType(filenameExtension: url.pathExtension) ?? type
            return PasteboardCapture(
                payload: .image(data: data, typeIdentifier: fileType.identifier))
        }
        if let png = (item as? UIImage)?.pngData() {
            return PasteboardCapture(
                payload: .image(data: png, typeIdentifier: UTType.png.identifier))
        }
        return nil
    }

    private func loadData(_ type: UTType, from provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadDataRepresentation(for: type) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }

    /// The file only exists inside the completion handler, so read it there.
    private func loadFile(_ type: UTType, from provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { continuation in
            _ = provider.loadFileRepresentation(for: type, openInPlace: false) { url, _, _ in
                continuation.resume(returning: url.flatMap { try? Data(contentsOf: $0) })
            }
        }
    }
}

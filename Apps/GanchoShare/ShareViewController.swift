import ClipboardCore
import GanchoAI
import GanchoKit
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Share-sheet entry point: extract text/URL/image attachments, then either
/// show what will be saved (title, boards, pin) or, with the instant switch
/// on, drop them in the App Group inbox at once.
///
/// Extensions live for seconds and must never own the store; the inbox file
/// handoff keeps GRDB single-owner in the host app (see `SharedInbox`), and
/// the boards come from the app's sealed snapshot.
final class ShareViewController: UIViewController {
    private var started = false

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !started else { return }
        started = true
        Task { await start() }
    }

    /// Fail closed: without the content key a deposit would leave plaintext
    /// clipboard content in the App Group container until the app's next
    /// launch. Losing one share is recoverable; leaking it is not.
    private func start() async {
        guard
            let key = try? StoreContentKey.load(
                keychainAccessGroup: KeychainPassphraseStore.iosSharedAccessGroup),
            let inbox = SharedInbox.inAppGroup(key: key)
        else { return finish(saved: false) }
        let captures = await preparedCaptures()
        guard !captures.isEmpty else { return finish(saved: false) }
        if ShareSheetPreference.savesInstantly() {
            let saved = captures.filter { (try? inbox.deposit($0)) != nil }.count
            return finish(saved: saved > 0)
        }
        let boards = SharedBoardSnapshot.inAppGroup(key: key)?.read() ?? []
        present(
            ShareSheetModel(
                captures: captures, suggestedTitle: suggestedTitle(for: captures), boards: boards,
                inbox: inbox))
    }

    private func present(_ model: ShareSheetModel) {
        let sheet = UIHostingController(
            rootView: ShareSheetView(
                model: model,
                onSave: { [weak self] in
                    if model.save() { self?.finish(saved: true) }
                },
                onCancel: { [weak self] in
                    self?.extensionContext?.completeRequest(returningItems: nil)
                }))
        addChild(sheet)
        sheet.view.frame = view.bounds
        sheet.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(sheet.view)
        sheet.didMove(toParent: self)
    }

    /// A success tap confirms the capture landed; an error tap says it did
    /// not, rather than letting the sheet vanish as though it had.
    private func finish(saved: Bool) {
        UINotificationFeedbackGenerator().notificationOccurred(saved ? .success : .error)
        extensionContext?.completeRequest(returningItems: nil)
    }

    private func suggestedTitle(for captures: [SharedInbox.PreparedCapture]) -> String? {
        let item = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem }.first
        return ShareTitleSuggestion.title(
            attributedTitle: item?.attributedTitle?.string,
            contentText: item?.attributedContentText?.string,
            sharedTexts: captures.compactMap(\.capture.textRepresentation))
    }

    /// Tier-0 classification runs HERE: deterministic, <5ms, no model loads,
    /// inside the extension memory ceiling.
    private func preparedCaptures() async -> [SharedInbox.PreparedCapture] {
        let providers = (extensionContext?.inputItems ?? [])
            .compactMap { $0 as? NSExtensionItem }
            .flatMap { $0.attachments ?? [] }
        let classifier = RuleClassifier()
        var prepared: [SharedInbox.PreparedCapture] = []
        for provider in providers {
            guard let capture = await capture(from: provider) else { continue }
            let kind: ClipContentKind? =
                switch capture.payload {
                case .image: .image
                default: capture.textRepresentation.map(classifier.classify)
                }
            prepared.append(SharedInbox.PreparedCapture(capture: capture, kind: kind))
        }
        return prepared
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

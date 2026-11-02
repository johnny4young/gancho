import AppKit
import ClipboardCore
import GanchoAI
import GanchoAppCore
import GanchoKit
import UniformTypeIdentifiers

/// The notch shelf: anything dragged to the notch lands on a board or runs an
/// image action. Dropped content goes through the same capture pipeline as a copy.
extension AppModel {
    /// Larger image files than the inline limit are still read for an action.
    nonisolated private static let maxActionImageBytes = 64 * 1024 * 1024

    func configureNotchShelf() {
        notchShelf.isAllowed = { [weak self] in self?.notchShelfAcceptsDrops ?? false }
        notchShelf.boards = { [weak self] in self?.boards ?? [] }
        notchShelf.counts = { [weak self] in
            (try? await self?.fullStore?.scopeCounts(excluding: []))?.boards ?? [:]
        }
        notchShelf.onDrop = { [weak self] target, content in
            self?.dropOnShelf(content, target: target)
        }
        #if DEBUG
            if CommandLine.arguments.contains("-ui-test-open-notch-shelf"),
                Self.uiTestDefaultsSuiteName() != nil
            {
                preferences.notchShelf = true
            }
        #endif
        notchShelf.setEnabled(preferences.notchShelf)
    }

    /// Never in Private Mode, while the screen is shared, or while a
    /// denylisted app is in front: that app is where the drag most likely started.
    private var notchShelfAcceptsDrops: Bool {
        shelfMayWrite && !monitor.denylist.contains(frontmostBundleID)
    }

    /// Re-checked after every await, since Private Mode or a share can start mid-action.
    private var shelfMayWrite: Bool {
        !preferences.isPrivateModePaused && sharingAppName == nil
    }

    private var frontmostBundleID: String? {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier
    }

    func dropOnShelf(_ content: NotchShelfDropContent, target: NotchShelfTarget) {
        Task {
            guard notchShelfAcceptsDrops else { return }
            switch target {
            case .board(let id):
                guard let board = boards.first(where: { $0.id == id }),
                    let item = await shelfClip(for: content), shelfMayWrite, !refusesSecret(item)
                else { return }
                _ = await drop(clipID: item.id, onBoard: board)
            case .newBoard:
                guard let item = await shelfClip(for: content), shelfMayWrite,
                    !refusesSecret(item), !pendingDeletionIDs.contains(item.id),
                    ClipSafeDelivery.isEligible(item)
                else { return }
                await createBoard(named: String(localized: "New board"), assigning: item)
            case .extractText, .resize, .stripLocation:
                await runShelfImageAction(target, on: content)
            }
        }
    }

    /// The dropped clip: one of ours read back, or new content saved like a copy.
    private func shelfClip(for content: NotchShelfDropContent) async -> ClipItem? {
        switch content {
        case .clip(let id):
            return try? await store.item(id: id)
        case .payload(let payload):
            guard shelfMayWrite,
                let outcome = await saveCapture(
                    PasteboardCapture(payload: payload, sourceAppBundleID: frontmostBundleID))
            else { return nil }
            enrich(outcome)
            return outcome.item
        }
    }

    /// Secrets stay out of boards; the saved clip keeps its expiry.
    private func refusesSecret(_ item: ClipItem) -> Bool {
        guard ClipSafePresentation.requiresMasking(item) else { return false }
        toasts.show(GanchoToast(message: "Secrets can’t be added to a board", style: .warning))
        return true
    }

    private func runShelfImageAction(
        _ target: NotchShelfTarget, on content: NotchShelfDropContent
    )
        async
    {
        guard let (data, type) = await shelfImage(for: content) else {
            copyHUD.show(CopyHUD(tile: .symbol("photo", danger: true), title: "Not an image"))
            return
        }
        switch target {
        case .extractText:
            await extractShelfText(from: data)
        case .resize:
            let outcome = await Task.detached { ImageEdits.resize(data) }.value
            await deliverShelfImage(
                outcome, original: (data, type), symbol: "photo", edited: "Resized · Copied",
                unchanged: "Already 1280 px or smaller · Copied")
        case .stripLocation:
            let outcome = await Task.detached { ImageEdits.stripLocation(data) }.value
            await deliverShelfImage(
                outcome, original: (data, type), symbol: "location.slash",
                edited: "Location removed · Copied", unchanged: "No location found · Copied")
        case .board, .newBoard:
            return
        }
    }

    private func shelfImage(for content: NotchShelfDropContent) async -> (Data, String)? {
        switch content {
        case .clip(let id):
            let payload = await ClipSafeDelivery.load(
                id: id, metadata: { try await self.store.item(id: $0) },
                content: { try await self.store.content(for: $0) })
            guard let payload, payload.item.kind == .image,
                case .binary(let data, let type) = payload.content
            else { return nil }
            return (data, type)
        case .payload(.image(let data, let type)):
            return (data, type)
        case .payload(.fileReferences(let urls)):
            guard urls.count == 1, let type = UTType(filenameExtension: urls[0].pathExtension),
                type.conforms(to: .image)
            else { return nil }
            let url = urls[0]
            let data = await Task.detached { () -> Data? in
                let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? .max
                guard size <= Self.maxActionImageBytes else { return nil }
                return try? Data(contentsOf: url)
            }.value
            return data.map { ($0, type.identifier) }
        case .payload:
            return nil
        }
    }

    /// Recognized text that reads as a secret is saved but never copied, the
    /// same rule as text recognized in a clip.
    private func extractShelfText(from data: Data) async {
        let text = (try? await ImageTextExtractor().extractText(from: data))?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let text, !text.isEmpty else {
            copyHUD.show(CopyHUD(tile: .symbol("text.viewfinder"), title: "No text found"))
            return
        }
        let isSecret = SensitiveDataDetector().detect(text) != nil
        guard shelfMayWrite else { return }
        if let outcome = await saveCapture(PasteboardCapture(text: text)) { enrich(outcome) }
        guard !isSecret else {
            copyHUD.show(
                CopyHUD(
                    tile: .symbol("lock.fill", danger: true), title: "Secret found · Not copied"))
            return
        }
        guard shelfMayWrite else { return }
        writeManualText(text)
        copyHUD.show(CopyHUD(tile: .symbol("text.viewfinder"), title: "Text extracted · Copied"))
    }

    private func deliverShelfImage(
        _ outcome: ImageEdits.Outcome, original: (Data, String), symbol: String,
        edited: LocalizedStringResource, unchanged: LocalizedStringResource
    ) async {
        let result: (data: Data, type: String)
        let title: LocalizedStringResource
        switch outcome {
        case .edited(let data, let type):
            (result, title) = ((data, type), edited)
        case .unchanged:
            (result, title) = (original, unchanged)
        case .failed:
            copyHUD.show(
                CopyHUD(tile: .symbol("photo", danger: true), title: "Couldn’t read that image"))
            return
        }
        guard shelfMayWrite else { return }
        let capture = PasteboardCapture(
            payload: .image(data: result.data, typeIdentifier: result.type))
        if let saved = await saveCapture(capture) { enrich(saved) }
        #if DEBUG
            // UI automation must never replace the user's clipboard.
            let writes = !CommandLine.arguments.contains("-ui-test-paste-sink")
        #else
            let writes = true
        #endif
        if writes {
            SystemPasteboardWriter().write(
                .binary(data: result.data, typeIdentifier: result.type), asPlainText: false)
        }
        copyHUD.show(CopyHUD(tile: .symbol(symbol), title: title))
    }
}

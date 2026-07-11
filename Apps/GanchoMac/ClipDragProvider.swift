import AppKit
import GanchoAppCore
import GanchoKit
import SwiftUI
import UniformTypeIdentifiers

/// Any history row or the peek header can be dragged into
/// another app. Registration is metadata-only so the drag starts instantly;
/// the clip's bytes load from the store only when a drop target accepts.
extension AppModel {
    func dragProvider(for item: ClipItem) -> NSItemProvider {
        let provider = NSItemProvider()
        // A non-draggable clip (sensitive) gets a fully inert provider: no
        // representations AND no metadata — `suggestedName` mirrors the
        // (possibly user-edited) title, which must not travel either, even
        // for a future caller that skips the `ClipDragSource` gate.
        let representations = ClipDragPayload.representations(for: item)
        guard !representations.isEmpty else { return provider }
        if !item.title.isEmpty {
            provider.suggestedName = item.title
        }
        // A drop target may load several of the advertised representations;
        // the clip's frecency bump must land once per drag, not once per load.
        let usage = OneShot()
        for representation in representations {
            register(representation, of: item, on: provider, usage: usage)
        }
        return provider
    }

    /// Collapses the N representation loads of one drag session into a single
    /// usage record. MainActor-isolated (the app default), so `claim()` can't
    /// race between loads.
    private final class OneShot {
        private var fired = false
        func claim() -> Bool {
            if fired { return false }
            fired = true
            return true
        }
    }

    private func register(
        _ representation: ClipDragPayload.Representation,
        of item: ClipItem,
        on provider: NSItemProvider,
        usage: OneShot
    ) {
        let identifier: String =
            switch representation {
            case .plainText: UTType.utf8PlainText.identifier
            case .url: UTType.url.identifier
            case .fileURL: UTType.fileURL.identifier
            case .pngImage: UTType.png.identifier
            }
        provider.registerDataRepresentation(
            forTypeIdentifier: identifier, visibility: .all
        ) { completion in
            Task { @MainActor in
                let content = try? await self.store.content(for: item.id)
                let data = content.flatMap { Self.data(for: representation, from: $0) }
                // Content-free by design: a drag that can't deliver says
                // nothing about what the clip holds.
                completion(data, data == nil ? CocoaError(.fileReadUnknown) : nil)
                // The target got real bytes → the drag delivered. Recorded
                // after completion so ranking bookkeeping never delays the drop.
                if data != nil, usage.claim() {
                    await self.noteDragOutDelivered(item)
                }
            }
            return nil
        }
    }

    /// The bytes for one representation of a loaded content; nil when the
    /// content can't provide it (the drop target falls back to a lower type).
    private static func data(
        for representation: ClipDragPayload.Representation, from content: ClipContent
    ) -> Data? {
        switch representation {
        case .plainText:
            return ClipDragPayload.plainText(for: content).map { Data($0.utf8) }
        case .url:
            guard let text = ClipDragPayload.plainText(for: content),
                let url = URL(string: text.trimmingCharacters(in: .whitespacesAndNewlines))
            else { return nil }
            return url.dataRepresentation
        case .fileURL:
            // SwiftUI's `.onDrag` vends ONE NSItemProvider = one drag item, so
            // a multi-file clip can only deliver its first file here; the
            // plain-text representation still carries every path. True
            // multi-item drag needs an AppKit drag source — a deliberate
            // non-goal for now.
            return ClipDragPayload.fileURLs(for: content).first?.dataRepresentation
        case .pngImage:
            guard case .binary(let data, let typeIdentifier) = content else { return nil }
            return pngData(from: data, typeIdentifier: typeIdentifier)
        }
    }

    /// Stored image blobs are PNG or TIFF (see `NSPasteboardReader`); PNG
    /// passes through, anything else is transcoded via `NSBitmapImageRep`.
    /// Bytes it can't decode return nil, which surfaces to the drop target
    /// as a content-free load error.
    private static func pngData(from data: Data, typeIdentifier: String) -> Data? {
        if typeIdentifier == UTType.png.identifier { return data }
        guard let bitmap = NSBitmapImageRep(data: data) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}

/// The single gate for drag-out: attaches `.onDrag` only when the clip is
/// draggable (sensitive clips never are) and keeps the panel from auto-hiding
/// while the drag is in flight.
struct ClipDragSource: ViewModifier {
    let item: ClipItem
    @Environment(AppModel.self) private var model

    @ViewBuilder
    func body(content: Content) -> some View {
        if ClipDragPayload.isDraggable(item) {
            content.onDrag {
                model.panel.noteDragOutStarted()
                return model.dragProvider(for: item)
            }
        } else {
            content
        }
    }
}

extension View {
    func clipDragSource(_ item: ClipItem) -> some View {
        modifier(ClipDragSource(item: item))
    }
}

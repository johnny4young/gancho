import AppKit
import GanchoAppCore
import GanchoKit
import SwiftUI
import UniformTypeIdentifiers

#if DEBUG
    extension Notification.Name {
        static let uiTestMultiFileDragPrepared = Self("uiTestMultiFileDragPrepared")
        static let uiTestMultiFileDragStarted = Self("uiTestMultiFileDragStarted")
    }
#endif

/// The materialized file payload for the narrow AppKit path. SwiftUI keeps
/// ownership of row state and selection; AppKit receives only concrete URLs
/// plus the clips whose usage should be recorded after a successful drop.
struct LoadedFileDragPayload: Equatable {
    let items: [ClipItem]
    let urls: [URL]
}

/// Any history row or the peek header can be dragged into another app.
/// Registration is metadata-only so the common SwiftUI drag starts instantly;
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
            // SwiftUI's path remains the lightweight source for one file. A
            // preflighted multi-file payload switches to the AppKit session
            // below, where every URL owns an NSDraggingItem.
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

    /// Loads only file-reference manifests (small path lists, never file
    /// bytes) to decide whether the row needs AppKit's multi-item drag source.
    /// One-file payloads return nil and stay on the existing lazy SwiftUI path.
    func preflightMultiFileDrag(for items: [ClipItem]) async -> LoadedFileDragPayload? {
        var contents: [ClipContent] = []
        for item in items {
            guard case .fileReferences(let paths)? = try? await store.content(for: item.id),
                !paths.isEmpty
            else { return nil }
            contents.append(.fileReferences(paths))
        }
        let urls = ClipDragPayload.uniqueFileURLs(for: contents)
        guard urls.count > 1 else { return nil }
        return LoadedFileDragPayload(items: items, urls: urls)
    }
}

/// The single gate for drag-out: attaches `.onDrag` only when the clip is
/// draggable (sensitive clips never are) and keeps the panel from auto-hiding
/// while the drag is in flight.
struct ClipDragSource: ViewModifier {
    let item: ClipItem
    let selectedItems: [ClipItem]
    let select: ((Bool) -> Void)?
    let doubleClick: (() -> Void)?
    @Environment(AppModel.self) private var model
    @State private var multiFilePayload: LoadedFileDragPayload?

    private var fileDragItems: [ClipItem] {
        ClipDragPayload.fileDragItems(dragged: item, selectedItems: selectedItems)
    }

    @ViewBuilder
    func body(content: Content) -> some View {
        if ClipDragPayload.isDraggable(item) {
            dragSource(content)
                .task(id: fileDragItems.map(\.id)) {
                    multiFilePayload = nil
                    // Only list rows opt into the AppKit capture view. Peek
                    // surfaces keep their established SwiftUI provider path.
                    guard select != nil, !fileDragItems.isEmpty else { return }
                    let payload = await model.preflightMultiFileDrag(for: fileDragItems)
                    guard !Task.isCancelled else { return }
                    multiFilePayload = payload
                    #if DEBUG
                        if CommandLine.arguments.contains("-show-multi-file-drop-target") {
                            NotificationCenter.default.post(
                                name: .uiTestMultiFileDragPrepared,
                                object: payload?.urls.count ?? 0)
                        }
                    #endif
                }
        } else {
            content
        }
    }

    @ViewBuilder
    private func dragSource(_ content: Content) -> some View {
        content
            .onDrag {
                model.panel.noteDragOutStarted()
                return model.dragProvider(for: item)
            }
            .overlay {
                if item.kind == .fileReference {
                    GeometryReader { geometry in
                        MultiFileDragEventBridge(
                            isActive: multiFilePayload != nil && select != nil,
                            select: select,
                            doubleClick: doubleClick
                        ) { sourceView, event in
                            guard let multiFilePayload else { return false }
                            return model.panel.beginMultiFileDrag(
                                multiFilePayload, event: event,
                                sourceView: sourceView, model: model)
                        }
                        .frame(width: geometry.size.width, height: geometry.size.height)
                    }
                }
            }
    }
}

/// Captures the left-mouse sequence only after a row has a preflighted
/// multi-file payload. Right-clicks still pass through to SwiftUI's context
/// menu; single/double clicks are forwarded explicitly so row semantics remain
/// unchanged while AppKit receives `mouseDragged(with:)` as the real responder.
private struct MultiFileDragEventBridge: NSViewRepresentable {
    let isActive: Bool
    let select: ((Bool) -> Void)?
    let doubleClick: (() -> Void)?
    let beginDrag: (NSView, NSEvent) -> Bool

    func makeNSView(context: Context) -> CaptureView {
        CaptureView()
    }

    func updateNSView(_ nsView: CaptureView, context: Context) {
        nsView.isActive = isActive
        nsView.select = select
        nsView.doubleClick = doubleClick
        nsView.beginDrag = beginDrag
    }

    final class CaptureView: NSView {
        var isActive = false
        var select: ((Bool) -> Void)?
        var doubleClick: (() -> Void)?
        var beginDrag: ((NSView, NSEvent) -> Bool)?
        private var dragStarted = false

        override func hitTest(_ point: NSPoint) -> NSView? {
            guard isActive, NSApp.currentEvent?.type == .leftMouseDown,
                bounds.contains(point)
            else { return nil }
            return self
        }

        override func mouseDown(with event: NSEvent) {
            dragStarted = false
        }

        override func mouseDragged(with event: NSEvent) {
            if !dragStarted { dragStarted = beginDrag?(self, event) == true }
        }

        override func mouseUp(with event: NSEvent) {
            guard !dragStarted else { return }
            if event.clickCount >= 2 {
                doubleClick?()
            } else {
                select?(event.modifierFlags.contains(.command))
            }
        }
    }
}

extension View {
    func clipDragSource(
        _ item: ClipItem,
        selectedItems: [ClipItem] = [],
        select: ((Bool) -> Void)? = nil,
        doubleClick: (() -> Void)? = nil
    ) -> some View {
        modifier(
            ClipDragSource(
                item: item, selectedItems: selectedItems,
                select: select, doubleClick: doubleClick))
    }
}

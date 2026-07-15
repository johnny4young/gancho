import Foundation
import GanchoKit

/// What a clip advertises to a drag-out session. Pure decisions only — the
/// panel registers representations up front (metadata is all it has; the drag
/// must start instantly) and loads bytes lazily when a drop target asks, so
/// this type answers "what types?" from `ClipItem` metadata and "what bytes?"
/// from a `ClipContent` the shell has already loaded.
///
/// Sensitive clips advertise NOTHING: dragging would hand the secret to any
/// drop target without the explicit Reveal step, so they are not drag sources
/// at all.
public enum ClipDragPayload {
    /// One pasteboard representation a drag source offers, highest-fidelity
    /// first (drop targets take the best type they accept).
    public enum Representation: Equatable, Sendable {
        /// `public.utf8-plain-text` — the clip's text.
        case plainText
        /// `public.url` — URL clips, so browsers/docks accept the link itself.
        case url
        /// `public.file-url` — file-reference clips; Finder copies the file.
        case fileURL
        /// `public.png` — image clips (TIFF blobs convert at load time).
        case pngImage
    }

    /// The representations `item` offers, in fidelity order. Empty means the
    /// clip is not draggable (today: exactly the sensitive clips).
    public static func representations(for item: ClipItem) -> [Representation] {
        representations(for: item.kind, isSensitive: item.isSensitive)
    }

    public static func representations(
        for kind: ClipContentKind, isSensitive: Bool
    ) -> [Representation] {
        guard !isSensitive else { return [] }
        switch kind {
        case .image: return [.pngImage]
        case .fileReference: return [.fileURL, .plainText]
        case .url: return [.url, .plainText]
        default: return [.plainText]
        }
    }

    public static func isDraggable(_ item: ClipItem) -> Bool {
        !representations(for: item).isEmpty
    }

    /// The file-reference clips represented by a drag that begins on `item`.
    /// A selected visible-order batch travels together only when every member
    /// is a non-sensitive file reference; mixed selections keep the historical
    /// behavior and drag only the row under the pointer.
    public static func fileDragItems(
        dragged item: ClipItem, selectedItems: [ClipItem]
    ) -> [ClipItem] {
        guard item.kind == .fileReference, !item.isSensitive else { return [] }
        guard selectedItems.contains(where: { $0.id == item.id }) else { return [item] }
        guard
            !selectedItems.isEmpty,
            selectedItems.allSatisfy({ $0.kind == .fileReference && !$0.isSensitive })
        else { return [item] }
        return selectedItems
    }

    /// The `public.utf8-plain-text` bytes for a loaded content, or nil when
    /// the content has no text form (binary blobs).
    public static func plainText(for content: ClipContent) -> String? {
        switch content {
        case .text(let text): return text
        case .fileReferences(let paths): return paths.joined(separator: "\n")
        case .binary: return nil
        }
    }

    /// The file URLs a file-reference clip points at; empty for other content.
    public static func fileURLs(for content: ClipContent) -> [URL] {
        guard case .fileReferences(let paths) = content else { return [] }
        return paths.map { URL(fileURLWithPath: $0) }
    }

    /// Flattens file-reference manifests into one stable drag order and drops
    /// duplicate paths so each concrete URL becomes exactly one drag item.
    public static func uniqueFileURLs(for contents: [ClipContent]) -> [URL] {
        var seen = Set<URL>()
        return contents.flatMap(fileURLs(for:)).filter {
            seen.insert($0.standardizedFileURL).inserted
        }
    }
}

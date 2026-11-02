import Foundation

/// The rows the keyboard typed into the current text field. Every inserted row
/// stays marked until the host's document changes, so a long message shows
/// what already went in. A clip handed off through the pasteboard is never
/// marked: it did not reach the field.
public struct KeyboardInsertedMarks: Sendable, Equatable {
    public private(set) var ids: Set<UUID> = []
    private var document: UUID?

    public init() {}

    public func contains(_ id: UUID) -> Bool { ids.contains(id) }

    /// The text a tap types into the field, or nil when the content can only
    /// travel through the pasteboard (a keyboard cannot type an image).
    public static func fieldText(for content: ClipContent) -> String? {
        switch content {
        case .text(let text): text
        case .fileReferences(let paths): paths.joined(separator: "\n")
        case .binary: nil
        }
    }

    /// Marks `id` as typed into `document`, first dropping marks that belong
    /// to an earlier document.
    public mutating func markInserted(_ id: UUID, into document: UUID) {
        observe(document: document)
        ids.insert(id)
    }

    /// Clears every mark when the host reports a different document.
    public mutating func observe(document: UUID) {
        guard document != self.document else { return }
        self.document = document
        ids.removeAll()
    }
}

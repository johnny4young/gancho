import Foundation

/// The Library snippet editor's working copy: the fields as the store holds
/// them and as the user has typed them. A reload from the store only moves the
/// stored side; a field the user changed keeps their text until it is saved,
/// and a field they have not touched follows the store.
public struct SnippetDraft: Sendable, Equatable {
    public struct Fields: Sendable, Equatable {
        public var title: String
        public var keyword: String
        public var body: String

        public init(title: String = "", keyword: String = "", body: String = "") {
            self.title = title
            self.keyword = keyword
            self.body = body
        }
    }

    public private(set) var snippetID: UUID?
    public private(set) var stored: Fields
    public var edited: Fields

    public init(snippetID: UUID? = nil, stored: Fields = Fields()) {
        self.snippetID = snippetID
        self.stored = stored
        self.edited = stored
    }

    public var isDirty: Bool { edited != stored }

    /// Adopt what the store now holds. Another snippet replaces the draft
    /// outright; the same snippet keeps every field the user has changed.
    public mutating func reload(snippetID: UUID, stored incoming: Fields) {
        guard snippetID == self.snippetID else {
            self = SnippetDraft(snippetID: snippetID, stored: incoming)
            return
        }
        edited = Fields(
            title: edited.title == stored.title ? incoming.title : edited.title,
            keyword: edited.keyword == stored.keyword ? incoming.keyword : edited.keyword,
            body: edited.body == stored.body ? incoming.body : edited.body)
        stored = incoming
    }

    /// The store accepted `saved` for `snippetID`. A save that lands after the
    /// editor moved to another snippet changes nothing here.
    public mutating func markSaved(snippetID: UUID, _ saved: Fields) {
        guard snippetID == self.snippetID else { return }
        stored = saved
    }
}

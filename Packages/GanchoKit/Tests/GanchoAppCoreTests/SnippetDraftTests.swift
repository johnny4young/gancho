import Foundation
import Testing

@testable import GanchoAppCore

@Suite("Snippet editor draft across store reloads")
struct SnippetDraftTests {
    private let first = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
    private let second = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
    private let stored = SnippetDraft.Fields(title: "Greeting", keyword: "hi", body: "Hello")

    @Test("Typed text survives a reload of the same snippet")
    func dirtyBodySurvivesReload() {
        var draft = SnippetDraft(snippetID: first, stored: stored)
        draft.edited.body = "Hello there"

        draft.reload(snippetID: first, stored: stored)

        #expect(draft.edited.body == "Hello there")
        #expect(draft.isDirty)
    }

    @Test("Fields the user has not touched follow the store")
    func untouchedFieldsFollowStore() {
        var draft = SnippetDraft(snippetID: first, stored: stored)
        draft.edited.body = "Hello there"
        var renamed = stored
        renamed.title = "Greeting (renamed elsewhere)"

        draft.reload(snippetID: first, stored: renamed)

        #expect(draft.edited.title == "Greeting (renamed elsewhere)")
        #expect(draft.edited.body == "Hello there")
        #expect(draft.stored == renamed)
    }

    @Test("A field edited back to its stored text follows the store like an untouched one")
    func restoredFieldFollowsStore() {
        var draft = SnippetDraft(snippetID: first, stored: stored)
        draft.edited.keyword = "hello"
        draft.edited.body = "Hello there"
        draft.edited.body = stored.body
        let incoming = SnippetDraft.Fields(title: "Greeting 2", keyword: "hi2", body: "Hello 2")

        draft.reload(snippetID: first, stored: incoming)

        #expect(draft.edited.keyword == "hello")
        #expect(draft.edited.body == "Hello 2")
        #expect(draft.edited.title == "Greeting 2")
    }

    @Test("Another snippet replaces the draft, edits and all")
    func otherSnippetReplaces() {
        var draft = SnippetDraft(snippetID: first, stored: stored)
        draft.edited.body = "Hello there"
        let other = SnippetDraft.Fields(title: "Sign-off", keyword: "bye", body: "Regards")

        draft.reload(snippetID: second, stored: other)

        #expect(draft.snippetID == second)
        #expect(draft.edited == other)
        #expect(!draft.isDirty)
    }

    @Test("A save settles the draft only for the snippet it was made on")
    func markSaved() {
        var draft = SnippetDraft(snippetID: first, stored: stored)
        draft.edited.body = "Hello there"

        draft.markSaved(snippetID: second, draft.edited)
        #expect(draft.isDirty)

        draft.markSaved(snippetID: first, draft.edited)
        #expect(!draft.isDirty)
        #expect(draft.stored.body == "Hello there")
    }

    @Test("An empty draft is never dirty")
    func emptyDraft() {
        #expect(!SnippetDraft().isDirty)
        #expect(SnippetDraft().snippetID == nil)
    }
}

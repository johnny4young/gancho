import ClipboardCore
import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

@Suite("Share sheet — which boards a shared clip joins")
struct ShareChoicesPlanTests {
    let favorites = Pinboard(name: "Favorites", isSystem: true)
    let work = Pinboard(name: "Work")
    let brand = Pinboard(name: "Brand")
    let link = ClipItem(kind: .url, preview: "https://example.com")

    @Test("Chosen boards that still exist are joined; a deleted one is skipped")
    func chosenBoards() {
        let choices = SharedInbox.ShareChoices(boardIDs: [work.id, UUID(), favorites.id])
        let plan = ShareChoicesPlan(
            choices, existing: [favorites, work, brand], item: link, isNew: true)
        #expect(Set(plan.boards.map(\.id)) == [work.id, favorites.id])
        #expect(plan.newBoardName == nil)
    }

    @Test("A typed board is created, or reused by name so a replay never duplicates it")
    func newBoard() {
        let create = ShareChoicesPlan(
            SharedInbox.ShareChoices(newBoardName: "  Recipes "), existing: [work], item: link,
            isNew: true)
        #expect(create.newBoardName == "Recipes")
        let reuse = ShareChoicesPlan(
            SharedInbox.ShareChoices(boardIDs: [work.id], newBoardName: "work"), existing: [work],
            item: link, isNew: true)
        #expect(reuse.newBoardName == nil)
        #expect(reuse.boards == [work], "the typed name joins the board once")
        let systemName = ShareChoicesPlan(
            SharedInbox.ShareChoices(newBoardName: "Favorites"), existing: [favorites],
            item: link, isNew: true)
        #expect(systemName.newBoardName == "Favorites", "a system board is never renamed into")
        #expect(
            ShareChoicesPlan(
                SharedInbox.ShareChoices(newBoardName: "   "), existing: [], item: link, isNew: true
            )
            .newBoardName == nil)
    }

    @Test("A protected clip takes no title and no pin; an existing title is kept")
    func protectedAndExisting() {
        let choices = SharedInbox.ShareChoices(title: "Typed", isPinned: true)
        let fresh = ShareChoicesPlan(choices, existing: [], item: link, isNew: true)
        #expect(fresh.title == "Typed")
        #expect(fresh.pins)
        let secret = ClipItem(kind: .secret, preview: "masked", isSensitive: true)
        let guarded = ShareChoicesPlan(choices, existing: [], item: secret, isNew: true)
        #expect(guarded.title == nil)
        #expect(!guarded.pins)
        var titled = link
        titled.title = "Mine"
        let duplicate = ShareChoicesPlan(choices, existing: [], item: titled, isNew: false)
        #expect(duplicate.title == nil, "sharing again never overwrites a title")
        var untitled = link
        untitled.isPinned = true
        let pinned = ShareChoicesPlan(choices, existing: [], item: untitled, isNew: false)
        #expect(pinned.title == "Typed")
        #expect(!pinned.pins, "already pinned")
    }
}

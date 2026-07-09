import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

@Suite("Board picker filter")
struct BoardPickerFilterTests {
    private let boards = [
        Pinboard(name: "Work"),
        Pinboard(name: "Design ideas"),
        Pinboard(name: "Personal")
    ]

    @Test("An empty query returns every board, in order")
    func emptyReturnsAll() {
        #expect(BoardPickerFilter.matches(boards, query: "   ").map(\.name) == boards.map(\.name))
    }

    @Test("Matching is case-insensitive substring, order preserved")
    func substringMatch() {
        #expect(BoardPickerFilter.matches(boards, query: "de").map(\.name) == ["Design ideas"])
        // Case-insensitive: "pers" matches only Personal.
        #expect(BoardPickerFilter.matches(boards, query: "PERS").map(\.name) == ["Personal"])
        // A substring shared by several ("n") returns all of them, in order.
        #expect(
            BoardPickerFilter.matches(boards, query: "n").map(\.name)
                == ["Design ideas", "Personal"])
    }

    @Test("A query with no match returns nothing")
    func noMatch() {
        #expect(BoardPickerFilter.matches(boards, query: "archive").isEmpty)
    }

    @Test("canCreate is true only for a non-empty, non-existing name")
    func createOffer() {
        #expect(BoardPickerFilter.canCreate(boards, query: "Archive"))
        #expect(!BoardPickerFilter.canCreate(boards, query: "  "))
        // An exact name (any case) already exists — don't offer to create it.
        #expect(!BoardPickerFilter.canCreate(boards, query: "work"))
        #expect(!BoardPickerFilter.canCreate(boards, query: "Design ideas"))
        // A partial match is still a distinct new name.
        #expect(BoardPickerFilter.canCreate(boards, query: "Design"))
    }
}

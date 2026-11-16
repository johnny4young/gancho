import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

@Suite("No matches — the caption and the row ↓ takes")
struct PanelNoMatchesTests {
    private func result(
        _ alternative: PanelSearchAlternative, _ total: Int
    )
        -> PanelAlternativeResult
    {
        PanelAlternativeResult(alternative: alternative, total: total, preview: [])
    }

    @Test("A filter alone never quotes an empty query back")
    func caption() {
        #expect(PanelNoMatches.caption(query: "", scopeName: nil) == .filter)
        #expect(PanelNoMatches.caption(query: "", scopeName: "Work") == .filter)
        #expect(PanelNoMatches.caption(query: "sour.e", scopeName: nil) == .query("sour.e"))
        #expect(
            PanelNoMatches.caption(query: "sour.e", scopeName: "Work")
                == .scoped(query: "sour.e", scope: "Work"))
    }

    @Test("Only the alternative with the most results is washed")
    func washed() {
        let results = [
            result(.mode(.exact), 0), result(.mode(.regex), 3), result(.mode(.meaning), 0)
        ]
        #expect(PanelNoMatches.washed(in: results) == .mode(.regex))
        #expect(
            PanelNoMatches.washed(in: results + [result(.allBoards, 5)]) == .allBoards)
    }

    @Test("A tie washes the gentler change of intent")
    func washedTie() {
        let results = [result(.mode(.regex), 2), result(.mode(.fuzzy), 2)]
        #expect(PanelNoMatches.washed(in: results) == .mode(.fuzzy))
    }

    @Test("Nothing is washed when every alternative is empty")
    func washedNone() {
        #expect(PanelNoMatches.washed(in: []) == nil)
        #expect(PanelNoMatches.washed(in: [result(.mode(.exact), 0)]) == nil)
    }

    @Test("Another word is suggested only when neither ↓ nor Clear filters helps")
    func suggestsAnotherWord() {
        let empty = [result(.mode(.exact), 0)]
        let found = [result(.mode(.regex), 3)]
        #expect(PanelNoMatches.suggestsAnotherWord(hasActiveFilter: false, results: empty))
        #expect(PanelNoMatches.suggestsAnotherWord(hasActiveFilter: false, results: []))
        #expect(!PanelNoMatches.suggestsAnotherWord(hasActiveFilter: false, results: found))
        #expect(!PanelNoMatches.suggestsAnotherWord(hasActiveFilter: true, results: empty))
    }
}

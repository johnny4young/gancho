import SwiftUI
import Testing

@testable import GanchoDesign

@Suite("Search field — its glyph says when previews are hidden")
@MainActor
struct SearchFieldTests {
    @Test("An eye-slash while previews are hidden, the magnifier otherwise")
    func glyph() {
        #expect(SearchField("Search", text: .constant("")).symbolName == "magnifyingglass")
        #expect(
            SearchField("Search", text: .constant(""), hidesPreviews: true).symbolName
                == "eye.slash")
    }

    @Test("The panel field draws the hook mark, and still the eye-slash while previews are hidden")
    func panelMark() {
        #expect(
            SearchField("Search", text: .constant(""), style: .bare, glyph: .mark).symbolName == nil
        )
        #expect(
            SearchField(
                "Search", text: .constant(""), style: .bare, glyph: .mark, hidesPreviews: true
            ).symbolName == "eye.slash")
    }
}

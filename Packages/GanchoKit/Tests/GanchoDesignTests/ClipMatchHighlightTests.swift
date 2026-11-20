import Foundation
import GanchoKit
import SwiftUI
import Testing

@testable import GanchoDesign

@Suite("Clip rows — search match marks")
@MainActor
struct ClipMatchHighlightTests {
    private func matches(_ query: String, in text: String) -> [String] {
        ClipMatchHighlight.ranges(of: .words(query), in: text).map { String(text[$0]) }
    }

    private func patternMatches(_ pattern: String, in text: String) -> [String] {
        ClipMatchHighlight.ranges(of: .pattern(pattern), in: text).map { String(text[$0]) }
    }

    @Test("A word is found wherever it occurs, whatever its case or accents")
    func caseAndAccents() {
        #expect(matches("launch", in: "Launch checklist, relaunch") == ["Launch", "launch"])
        #expect(matches("cafe", in: "Café menu") == ["Café"])
    }

    @Test("Each query word is marked on its own, in text order")
    func severalWords() {
        #expect(matches("kit press", in: "Press kit — Gancho") == ["Press", "kit"])
    }

    @Test("Overlapping and repeated words merge into one mark")
    func merged() {
        #expect(matches("launch laun launch", in: "launch-plan.pdf") == ["launch"])
        #expect(matches("ab bc", in: "abc") == ["abc"])
    }

    @Test("Nothing to mark: a blank query, or words the text does not hold")
    func noMatch() {
        #expect(matches("   ", in: "Launch checklist").isEmpty)
        #expect(matches("lnch", in: "Launch checklist").isEmpty)
        #expect(matches("launch", in: "").isEmpty)
    }

    @Test("A pattern marks each of its matches, ignoring case")
    func pattern() {
        #expect(patternMatches("sour.e", in: "Safari SOURCE link") == ["SOURCE"])
        #expect(patternMatches("\\d+", in: "rgb 255 107 74") == ["255", "107", "74"])
        // Leftmost alternative wins, as in search.
        #expect(patternMatches("a|ab", in: "abc") == ["a"])
    }

    @Test("A pattern marks nothing when invalid, unmatched or only empty")
    func patternNoMatch() {
        #expect(patternMatches("sour(", in: "source").isEmpty)
        #expect(patternMatches("xyz", in: "source").isEmpty)
        #expect(patternMatches("x*", in: "source").isEmpty)
        #expect(patternMatches(".", in: "").isEmpty)
    }

    @Test("A pattern reads no further than a row shows")
    func patternHaystackLimit() {
        let limit = ClipMatchHighlight.patternHaystackLimit
        let text = String(repeating: "a", count: limit) + "b"
        #expect(patternMatches("a+b", in: text).isEmpty)
        #expect(patternMatches("a+", in: text) == [String(repeating: "a", count: limit)])
    }

    @Test("A pattern's mark never splits a character")
    func patternWholeCharacters() {
        // `.` takes one code point; the flag is two, so the mark widens to it.
        #expect(patternMatches("^.", in: "🇨🇴 Bogotá") == ["🇨🇴"])
        #expect(patternMatches("a.", in: "ab ac") == ["ab", "ac"])
    }

    @Test("A mark is emphasised and underlined; the rest keeps its attributes")
    func attributes() {
        var source = AttributedString("gancho.app/launch")
        source.foregroundColor = GanchoTokens.Palette.ink3
        let marked = ClipMatchHighlight.marked(source, match: .words("LAUNCH"))
        let runs = marked.runs.map { run in
            (String(marked[run.range].characters), run.swiftUI.underlineStyle != nil)
        }
        #expect(runs.map(\.0) == ["gancho.app/", "launch"])
        #expect(runs.map(\.1) == [false, true])
        let match = marked.runs.first { $0.swiftUI.underlineStyle != nil }
        #expect(match?.inlinePresentationIntent == .stronglyEmphasized)
        #expect(match?.swiftUI.foregroundColor == GanchoTokens.Palette.ink)
        #expect(marked.runs.first?.swiftUI.foregroundColor == GanchoTokens.Palette.ink3)
        #expect(String(marked.characters) == "gancho.app/launch")
    }

    @Test("A pattern's matches are marked like words")
    func patternAttributes() {
        let marked = ClipMatchHighlight.marked(
            AttributedString("Xcode source sample"), match: .pattern("sour.e"))
        let underlined = marked.runs.filter { $0.swiftUI.underlineStyle != nil }
            .map { String(marked[$0.range].characters) }
        #expect(underlined == ["source"])
    }

    @Test("A masked row never carries the match; an ordinary one does")
    func maskedRowsNeverMark() {
        let secret = ClipItem(kind: .secret, title: "launch key", contentHash: "s")
        #expect(ClipCard(item: secret, match: .words("launch")).match == nil)
        #expect(ClipCard(item: secret, match: .pattern("laun.h")).match == nil)
        let text = ClipItem(kind: .text, title: "launch notes", contentHash: "t")
        #expect(ClipCard(item: text, previewsHidden: true, match: .words("launch")).match == nil)
        #expect(ClipCard(item: text, match: .words("launch")).match == .words("launch"))
        #expect(ClipCard(item: text, match: .pattern("laun.h")).match == .pattern("laun.h"))
        #expect(ClipCard(item: text, match: .words("  ")).match == nil)
        #expect(ClipCard(item: text, match: .pattern(" ")).match == nil)
        #expect(ClipCard(item: text).match == nil)
    }
}

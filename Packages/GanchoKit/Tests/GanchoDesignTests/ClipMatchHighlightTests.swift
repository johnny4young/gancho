import Foundation
import GanchoKit
import SwiftUI
import Testing

@testable import GanchoDesign

@Suite("Clip rows — search match marks")
@MainActor
struct ClipMatchHighlightTests {
    private func matches(_ query: String, in text: String) -> [String] {
        ClipMatchHighlight.ranges(of: query, in: text).map { String(text[$0]) }
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

    @Test("A mark is emphasised and underlined; the rest keeps its attributes")
    func attributes() {
        var source = AttributedString("gancho.app/launch")
        source.foregroundColor = GanchoTokens.Palette.ink3
        let marked = ClipMatchHighlight.marked(source, query: "LAUNCH")
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

    @Test("A masked row never carries the query; an ordinary one does")
    func maskedRowsNeverMark() {
        let secret = ClipItem(kind: .secret, title: "launch key", contentHash: "s")
        #expect(ClipCard(item: secret, matchQuery: "launch").matchQuery == nil)
        let text = ClipItem(kind: .text, title: "launch notes", contentHash: "t")
        #expect(ClipCard(item: text, previewsHidden: true, matchQuery: "launch").matchQuery == nil)
        #expect(ClipCard(item: text, matchQuery: "launch").matchQuery == "launch")
        #expect(ClipCard(item: text, matchQuery: "  ").matchQuery == nil)
        #expect(ClipCard(item: text).matchQuery == nil)
    }
}

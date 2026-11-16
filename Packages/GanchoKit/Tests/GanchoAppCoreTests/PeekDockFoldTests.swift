import Testing

@testable import GanchoAppCore

@Suite("Peek dock — which verbs fold as it narrows")
struct PeekDockFoldTests {
    private let text = [
        "preview-paste", "preview-paste-plain", "preview-pin", "preview-board", "preview-stack",
        "preview-context"
    ]

    private func rows(_ ids: [String]) -> [[String]] {
        PeekDockFold.tiers(for: ids).map(\.visible)
    }

    @Test("The widest tier shows every verb; Context, then Stack, fold first")
    func widestFirst() {
        let tiers = rows(text)
        #expect(tiers[0] == text)
        #expect(tiers[1] == Array(text.dropLast()))
        #expect(tiers[2] == Array(text.dropLast(2)))
    }

    @Test("Pin and Board fold together, into Actions, and keep the dock's order")
    func pinAndBoardFoldTogether() {
        let tiers = rows(text)
        #expect(tiers[3] == ["preview-paste", "preview-paste-plain"])
        #expect(
            PeekDockFold.folded(from: text, showing: tiers[3])
                == ["preview-pin", "preview-board", "preview-stack", "preview-context"])
        #expect(!tiers.contains { $0.contains("preview-pin") != $0.contains("preview-board") })
    }

    @Test("Paste plain folds last and Return's verb never does")
    func primaryStays() {
        #expect(rows(text).last == ["preview-paste"])
        #expect(rows(text).allSatisfy { $0.first == "preview-paste" })
        #expect(rows(["preview-pin", "preview-board"]).last == ["preview-pin"])
        #expect(rows(["preview-paste"]) == [["preview-paste"]])
        #expect(rows([]).isEmpty)
    }

    @Test("A kind's own verb outlasts Pin, Board and Stack")
    func kindVerb() {
        let image = [
            "preview-paste", "preview-paste-plain", "image-copy-text", "preview-pin",
            "preview-board", "preview-stack"
        ]
        let tiers = rows(image)
        #expect(tiers[2] == ["preview-paste", "preview-paste-plain", "image-copy-text"])
        #expect(tiers[3] == ["preview-paste", "preview-paste-plain"])
    }

    @Test("Every tier keeps the dock's order and each is narrower than the last")
    func orderAndUniqueness() {
        let tiers = rows(text)
        for tier in tiers {
            #expect(tier == text.filter(tier.contains))
        }
        for (wider, narrower) in zip(tiers, tiers.dropFirst()) {
            #expect(narrower.count < wider.count)
        }
    }

    @Test("A short name for Return's verb is tried before folding the next verb")
    func shortPrimary() {
        let tiers = PeekDockFold.tiers(for: text, primaryHasShortTitle: true)
        #expect(tiers.count == rows(text).count * 2)
        #expect(tiers[0] == PeekDockFold.Tier(visible: text, shortPrimary: false))
        #expect(tiers[1] == PeekDockFold.Tier(visible: text, shortPrimary: true))
        #expect(tiers[2].visible == Array(text.dropLast()) && !tiers[2].shortPrimary)
        #expect(PeekDockFold.tiers(for: text).allSatisfy { !$0.shortPrimary })
    }
}

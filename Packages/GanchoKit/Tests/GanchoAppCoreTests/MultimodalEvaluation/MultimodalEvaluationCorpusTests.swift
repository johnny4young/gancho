import CoreGraphics
import Foundation
import ImageIO
import Testing

/// Guards the frozen corpus and the scoring arithmetic. No OCR or model runs here.
@Suite("Multimodal evaluation corpus")
struct MultimodalEvaluationCorpusTests {
    private typealias Corpus = MultimodalEvaluationCorpus

    @Test("100 captures with unique keys and ids, 85 rendered images and 15 text notes")
    func captureInventory() {
        let captures = Corpus.captures
        #expect(captures.count == 100)
        #expect(Set(captures.map(\.key)).count == 100)
        #expect(Set(captures.map(\.id)).count == 100)
        #expect(captures.filter(\.scene.isImage).count == 85)
    }

    @Test("30 queries split 15 English and 15 Spanish, with at least six unanswered")
    func queryInventory() {
        let queries = Corpus.queries
        #expect(queries.count == 30)
        #expect(Set(queries.map(\.name)).count == 30)
        #expect(queries.filter { $0.language == "en" }.count == 15)
        #expect(queries.filter { $0.language == "es" }.count == 15)
        #expect(queries.filter { $0.category == .unanswered }.count == 6)
    }

    @Test("Each language covers every category in both calibration and held-out")
    func categoryCoverage() {
        for language in ["en", "es"] {
            for category in Corpus.Category.allCases {
                let matching = Corpus.queries.filter {
                    $0.language == language && $0.category == category
                }
                #expect(matching.contains { !$0.heldOut }, "\(language) \(category) calibration")
                #expect(matching.contains { $0.heldOut }, "\(language) \(category) held-out")
            }
        }
    }

    @Test("Answered queries resolve to existing captures; unanswered ones expect nothing")
    func expectedAnswers() {
        for query in Corpus.queries {
            let ids = Corpus.expectedIDs(query)
            #expect(ids.count == query.expectedKeys.count, "\(query.name) names a missing key")
            #expect(
                (query.category == .unanswered) == query.expectedKeys.isEmpty,
                "\(query.name) category and answers disagree")
        }
    }

    @Test("Calibration and held-out queries never share an expected capture")
    func splitIsDisjoint() {
        let calibration = Set(Corpus.queries.filter { !$0.heldOut }.flatMap(\.expectedKeys))
        let heldOut = Set(Corpus.queries.filter(\.heldOut).flatMap(\.expectedKeys))
        #expect(calibration.isDisjoint(with: heldOut))
    }

    @Test("Visual-only answers are shape scenes, which carry no text to read")
    func visualOnlyAnswersHaveNoText() throws {
        for query in Corpus.queries where query.category == .visualOnly {
            for key in query.expectedKeys {
                let scene = try #require(Corpus.capturesByKey[key]?.scene)
                guard case .shapes = scene else {
                    Issue.record("\(query.name) expects \(key), which is not a shape scene")
                    continue
                }
            }
        }
    }

    @Test("Visual-relation answers have a hard negative that OCR text cannot separate")
    func visualRelationHardNegatives() throws {
        for query in Corpus.queries where query.category == .visualRelation {
            for key in query.expectedKeys {
                let target = try #require(Corpus.capturesByKey[key])
                let twins = Corpus.captures.filter {
                    $0.key != key && Self.words($0.scene) == Self.words(target.scene)
                }
                #expect(!twins.isEmpty, "\(query.name): no capture shares \(key)'s words")
            }
        }
    }

    @Test("Every image renders as a decodable PNG of the canvas size, identically twice")
    func rendering() throws {
        for capture in Corpus.captures where capture.scene.isImage {
            let first = try SyntheticCaptureRenderer.png(for: capture.scene)
            let second = try SyntheticCaptureRenderer.png(for: capture.scene)
            #expect(first == second, "\(capture.key) is not deterministic")
            let source = try #require(CGImageSourceCreateWithData(first as CFData, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            #expect(image.width == Int(SyntheticCaptureRenderer.size.width))
            #expect(image.height == Int(SyntheticCaptureRenderer.size.height))
        }
    }

    @Test("Text notes are stored as text, never rendered")
    func textScenesDoNotRender() {
        #expect(throws: SyntheticCaptureRenderer.RenderError.textScene) {
            try SyntheticCaptureRenderer.png(for: .text("note"))
        }
    }

    /// Order-insensitive words, the most OCR text can tell about a scene.
    private static func words(_ scene: Corpus.Scene) -> [String] {
        let text: String
        switch scene {
        case .dialog(let title, let message, let code):
            text = [title, message, code].joined(
                separator: " ")
        case .diagram(let nodes): text = nodes.joined(separator: " ")
        case .barChart(let title, let labels, _): text = ([title] + labels).joined(separator: " ")
        case .statusScreen(let title, let lines): text = ([title] + lines).joined(separator: " ")
        case .shapes: text = ""
        case .text(let body): text = body
        }
        return text.split(separator: " ").map(String.init).sorted()
    }
}

@Suite("Multimodal retrieval scorecard")
struct MultimodalRetrievalScorecardTests {
    private let image = UUID()
    private let note = UUID()
    private let other = UUID()

    private func query(
        _ category: MultimodalEvaluationCorpus.Category = .ocrParaphrase
    ) -> MultimodalEvaluationCorpus.Query {
        .init(
            name: "sample", language: "en", category: category, heldOut: false, text: "q",
            expectedKeys: [])
    }

    @Test("A hit at rank 3 counts as recall 1 and reciprocal rank 1/3")
    func hitBelowTop() throws {
        var card = MultimodalRetrievalScorecard(cutoff: 5, imageIDs: [image])
        card.record(query(), expected: [note], ranked: [other, image, note])
        let tally = card.total()
        #expect(tally.answered == 1)
        #expect(tally.recall == 1)
        #expect(try #require(tally.meanReciprocalRank).isApproximatelyEqual(to: 1.0 / 3.0))
        #expect(tally.misses.isEmpty)
        #expect(tally.wrongTopImage == 0, "the first result is not an image")
    }

    @Test("An answer past the cutoff is a miss with recall 0")
    func pastCutoff() {
        var card = MultimodalRetrievalScorecard(cutoff: 2, imageIDs: [])
        card.record(query(), expected: [note], ranked: [other, image, note])
        let tally = card.total()
        #expect(tally.recall == 0)
        #expect(tally.meanReciprocalRank == 0)
        #expect(tally.misses == ["sample"])
    }

    @Test("Recall is the fraction of expected ids found when several are expected")
    func partialRecall() {
        var card = MultimodalRetrievalScorecard(cutoff: 5, imageIDs: [])
        card.record(query(), expected: [note, other], ranked: [note])
        #expect(card.total().recall == 0.5)
    }

    @Test("An unexpected image ranked first counts as a wrong image selection")
    func wrongTopImage() {
        var card = MultimodalRetrievalScorecard(cutoff: 5, imageIDs: [image])
        card.record(query(), expected: [note], ranked: [image, note])
        #expect(card.total().wrongTopImage == 1)
    }

    @Test("Unanswered queries count results separately and never affect recall")
    func unanswered() {
        var card = MultimodalRetrievalScorecard(cutoff: 5, imageIDs: [])
        card.record(query(.unanswered), expected: [], ranked: [note])
        card.record(query(.unanswered), expected: [], ranked: [])
        let tally = card.total()
        #expect(tally.unanswered == 2)
        #expect(tally.unansweredWithResults == 1)
        #expect(tally.answered == 0)
        #expect(tally.recall == nil)
    }
}

extension Double {
    fileprivate func isApproximatelyEqual(to other: Double) -> Bool {
        abs(self - other) < 1e-9
    }
}

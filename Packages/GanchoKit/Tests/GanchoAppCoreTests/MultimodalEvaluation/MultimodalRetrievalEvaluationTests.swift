import Foundation
import GanchoAI
import GanchoKit
import Testing

/// Opt-in: real Vision OCR and the real contextual model over the frozen corpus.
/// Missing model assets fail the run instead of skipping it.
@Suite(
    "Multimodal retrieval baselines",
    .enabled(if: ProcessInfo.processInfo.environment["GANCHO_MULTIMODAL_EVALUATION"] == "1"))
struct MultimodalRetrievalEvaluationTests {
    private typealias Corpus = MultimodalEvaluationCorpus
    private static let cutoff = 5

    @Test func compareOCRBaselines() async throws {
        let embedder = try #require(ContextualSentenceEmbedder())
        try #require(
            embedder.hasAvailableAssets, "Real model assets are required; no download is started")
        let clock = ContinuousClock()
        let started = clock.now
        let fixture = try await MultimodalEvaluationFixture.make(captures: Corpus.captures)
        let seeding = clock.now - started

        for capture in Corpus.captures {
            if case .shapes = capture.scene {
                #expect(
                    fixture.searchableText[capture.id] == nil,
                    "\(capture.key) must stay text-free for visual-only queries")
            }
        }

        let lexical = OCRLexicalStrategy(store: fixture.store)
        let semantic = try OCRSemanticStrategy(fixture: fixture, embedder: embedder)
        var cards: [String: MultimodalRetrievalScorecard] = [:]
        for strategy in [lexical, semantic] as [any MultimodalRetrievalStrategy] {
            var card = MultimodalRetrievalScorecard(
                cutoff: Self.cutoff, imageIDs: fixture.imageIDs)
            for query in Corpus.queries {
                let ranked = try await strategy.rank(query.text, limit: Self.cutoff)
                card.record(query, expected: Corpus.expectedIDs(query), ranked: ranked)
            }
            cards[strategy.name] = card
        }

        let lexicalCard = try #require(cards[lexical.name])
        #expect(
            lexicalCard.total(where: { $0.category == .identifier }).recall == 1,
            "Rendered identifiers must be found through OCR text")
        #expect(
            lexicalCard.total(where: { $0.category == .unanswered }).unansweredWithResults == 0)

        print(try receipt(cards: cards, fixture: fixture, seeding: seeding))
    }

    // MARK: - Receipt

    private func receipt(
        cards: [String: MultimodalRetrievalScorecard], fixture: MultimodalEvaluationFixture,
        seeding: Duration
    ) throws -> String {
        let withText = fixture.imageIDs.filter { fixture.searchableText[$0] != nil }.count
        let rows = cards.mapValues { card in
            card.tallies.sorted { $0.key < $1.key }.map { bucket, tally in
                ReceiptRow(
                    bucket: bucket.label, answered: tally.answered,
                    recallAtCutoff: tally.recall, mrrAtCutoff: tally.meanReciprocalRankAtCutoff,
                    wrongTopImage: tally.wrongTopImage, unanswered: tally.unanswered,
                    unansweredWithResults: tally.unansweredWithResults, misses: tally.misses)
            }
        }
        let receipt = Receipt(
            corpusRevision: Corpus.revision, cutoff: Self.cutoff,
            environment: .init(
                operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
                hardwareModel: Self.hardwareModel(),
                ocr: "Vision RecognizeTextRequest, accurate, language correction",
                textEmbedding: "NLContextualEmbedding English, mean-pooled",
                embeddingStoreVersion: EmbeddingModelInfo.currentVersion),
            imagesWithOCRText: "\(withText)/\(fixture.imageIDs.count)",
            seedingSeconds: seeding / .seconds(1),
            strategies: rows)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let json = String(bytes: try encoder.encode(receipt), encoding: .utf8) ?? ""
        return "Multimodal evaluation receipt:\n" + json
    }

    private static func hardwareModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let bytes = model.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        return String(bytes: bytes, encoding: .utf8) ?? "unknown"
    }
}

private struct Receipt: Encodable {
    let corpusRevision: Int
    let cutoff: Int
    let environment: ReceiptEnvironment
    let imagesWithOCRText: String
    let seedingSeconds: Double
    let strategies: [String: [ReceiptRow]]
}

private struct ReceiptEnvironment: Encodable {
    let operatingSystem: String
    let hardwareModel: String
    let ocr: String
    let textEmbedding: String
    let embeddingStoreVersion: Int
}

private struct ReceiptRow: Encodable {
    let bucket: String
    let answered: Int
    let recallAtCutoff: Double?
    let mrrAtCutoff: Double?
    let wrongTopImage: Int
    let unanswered: Int
    let unansweredWithResults: Int
    let misses: [String]
}

import Foundation
import GRDB
import GanchoAI
@_spi(GanchoInternal) import GanchoKit
import Testing

@testable import GanchoAppCore

/// Opt-in, REAL contextual embeddings. Missing assets are a failure, not a passing skip.
@Suite(
    "Hybrid retrieval real relevance",
    .enabled(if: ProcessInfo.processInfo.environment["GANCHO_SEMANTIC_EVALUATION"] == "1"))
struct HybridRelevanceEvaluationTests {
    private struct Receipt {
        var lexicalParaphrases = 0
        var hybridParaphrases = 0
        var paraphrases = 0
        var unansweredRelated = 0
        var unanswered = 0
    }

    @Test func evaluateEnglishAndSpanishHeldOutRecall() async throws {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(
                directory: FileManager.default.temporaryDirectory.appendingPathComponent(
                    "relevance-\(UUID())")))
        try store.migrate()
        let board = try await store.createPinboard(name: "Evaluation", sfSymbol: "folder")
        let embedder = try #require(ContextualSentenceEmbedder())
        #expect(
            embedder.hasAvailableAssets, "Real model assets are required; no download is started")
        try await seed(store: store, embedder: embedder, boardID: board.id)
        let corpus = HybridEvaluationCorpus.queries(boardID: board.id)
        #expect(corpus.count == 120)
        var receipts: [String: Receipt] = [:]
        for sample in corpus {
            let lexical = try await store.search(sample.query, limit: 5)
            let result = try await HybridRetrieval().search(
                sample.query, store: store, queryVector: embedder.vector(for: sample.query.text),
                conventionalLimit: 5, relatedLimit: 5)
            #expect(result.conventional == lexical, "Literal ranking must not change")
            let key = sample.language + (sample.heldOut ? "-held-out" : "-calibration")
            var receipt = receipts[key] ?? Receipt()
            if sample.category == .paraphrase {
                receipt.paraphrases += 1
                if !Set(lexical.prefix(5).map(\.id)).isDisjoint(with: sample.expected) {
                    receipt.lexicalParaphrases += 1
                }
                if !Set(result.ordered.prefix(5).map(\.id)).isDisjoint(with: sample.expected) {
                    receipt.hybridParaphrases += 1
                }
            } else if sample.category == .literal || sample.category == .filtered {
                #expect(!Set(result.ordered.prefix(5).map(\.id)).isDisjoint(with: sample.expected))
            } else {
                #expect(lexical.isEmpty)
                receipt.unanswered += 1
                if !result.related.isEmpty { receipt.unansweredRelated += 1 }
            }
            receipts[key] = receipt
        }
        for key in receipts.keys.sorted() {
            let receipt = try #require(receipts[key])
            let lexical = Double(receipt.lexicalParaphrases) / Double(receipt.paraphrases)
            let hybrid = Double(receipt.hybridParaphrases) / Double(receipt.paraphrases)
            print(
                "Semantic evaluation \(key): Recall@5 lexical=\(lexical) hybrid=\(hybrid); unanswered suggestions=\(receipt.unansweredRelated)/\(receipt.unanswered)"
            )
            if key.hasSuffix("held-out") { #expect(hybrid - lexical >= 0.10) }
        }
    }

    private func seed(
        store: GRDBClipboardStore, embedder: ContextualSentenceEmbedder, boardID: UUID
    ) async throws {
        for language in ["en", "es"] {
            for (index, topic) in HybridEvaluationCorpus.topics.enumerated() {
                let body =
                    (language == "en" ? topic.english : topic.spanish)
                    + " REF\(language.uppercased())\(index)"
                let item = ClipItem(
                    id: HybridEvaluationCorpus.identifier(language: language, index: index),
                    preview: body, contentHash: "\(language)-\(index)",
                    sourceAppBundleID: "evaluation.notes",
                    isPinned: !index.isMultiple(of: 2))
                try await store.insert(item, content: .text(body))
                try await store.saveEmbedding(clipID: item.id, vector: embedder.vector(for: body))
                if index.isMultiple(of: 2) {
                    try await store.assign(clipID: item.id, toBoard: boardID)
                }
            }
        }
    }
}

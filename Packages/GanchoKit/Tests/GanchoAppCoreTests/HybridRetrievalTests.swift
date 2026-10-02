import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

private actor HybridContractStore: ClipSearching, ScopedSemanticSearching {
    enum Failure { case none, unavailable, cancelled }
    var literal: [ClipItem]
    let related: [ClipItem]
    let failure: Failure
    let removesLiteral: Bool
    private(set) var semanticCalls = 0
    private(set) var seenQuery: ClipSearchQuery?

    init(
        literal: [ClipItem], related: [ClipItem] = [], failure: Failure = .none,
        removesLiteral: Bool = false
    ) {
        self.literal = literal
        self.related = related
        self.failure = failure
        self.removesLiteral = removesLiteral
    }
    func search(_ query: ClipSearchQuery, limit: Int) -> [ClipItem] {
        Array(literal.filter { query.includedIDs?.contains($0.id) ?? true }.prefix(max(0, limit)))
    }
    func semanticSearch(
        queryVector: [Float], query: ClipSearchQuery, topK: Int, snippetsOnly: Bool
    ) throws -> [ClipItem] {
        semanticCalls += 1
        seenQuery = query
        if removesLiteral { literal = [] }
        switch failure {
        case .none: return Array(related.prefix(max(0, topK)))
        case .unavailable: throw CocoaError(.fileReadUnknown)
        case .cancelled: throw CancellationError()
        }
    }
    func semanticSearch(queryVector: [Float], topK: Int, snippetsOnly: Bool) -> [ClipItem] { [] }
    func items(matching rule: SmartCollectionRule, limit: Int) -> [ClipItem] { [] }
}

@Suite("Hybrid retrieval contracts")
struct HybridRetrievalTests {
    @Test func literalOrderWinsAndDuplicatesNeverConsumeSlots() async throws {
        let first = ClipItem(preview: "First", contentHash: "first")
        let second = ClipItem(preview: "Second", contentHash: "second")
        let third = ClipItem(preview: "Related", contentHash: "related")
        let store = HybridContractStore(literal: [second, first], related: [first, third, third])
        let query = ClipSearchQuery(text: "meaning", kinds: [.text], pinnedOnly: true)
        let result = try await HybridRetrieval().search(query, store: store, queryVector: [1])
        #expect(result.ordered.map(\.id) == [second.id, first.id, third.id])
        #expect(await store.seenQuery == query)
        #expect(result.semanticState == .ready)
    }

    @Test(arguments: [
        ClipSearchQuery(text: ""), ClipSearchQuery(text: " \n"),
        ClipSearchQuery(text: ".*", mode: .regex)
    ])
    func ineligibleQueriesNeverReachSemantic(_ query: ClipSearchQuery) async throws {
        let store = HybridContractStore(literal: [])
        let result = try await HybridRetrieval().search(query, store: store, queryVector: [1])
        #expect(result.semanticState == .notRequested)
        #expect(await store.semanticCalls == 0)
    }

    @Test func unavailableVectorsPreserveOrdinarySearch() async throws {
        let item = ClipItem(preview: "Literal", contentHash: "literal")
        let store = HybridContractStore(literal: [item])
        let result = try await HybridRetrieval().search(
            ClipSearchQuery(text: "Literal"), store: store, queryVector: nil)
        #expect(result.conventional == [item])
        #expect(await store.semanticCalls == 0)
    }

    @Test func deletionsDuringSemanticAreRevalidatedEvenOnFallback() async throws {
        let item = ClipItem(preview: "Literal", contentHash: "literal")
        for failure in [HybridContractStore.Failure.none, .unavailable] {
            let store = HybridContractStore(literal: [item], failure: failure, removesLiteral: true)
            let result = try await HybridRetrieval().search(
                ClipSearchQuery(text: "Literal"), store: store, queryVector: [1])
            #expect(result.conventional.isEmpty)
        }
    }

    @Test func cancellationNeverTurnsIntoFallbackSuccess() async throws {
        let store = HybridContractStore(literal: [], failure: .cancelled)
        await #expect(throws: CancellationError.self) {
            try await HybridRetrieval().search(
                ClipSearchQuery(text: "query"), store: store, queryVector: [1])
        }
    }

    @Test func corpusPartitionsHaveNoTopicLeakage() {
        let queries = HybridEvaluationCorpus.queries(boardID: UUID())
        #expect(queries.count == 120)
        for language in ["en", "es"] {
            let calibration = queries.filter { $0.language == language && !$0.heldOut }
            let reserved = queries.filter { $0.language == language && $0.heldOut }
            #expect(calibration.count == 30)
            #expect(reserved.count == 30)
            #expect(
                Set(calibration.flatMap(\.expected)).isDisjoint(with: reserved.flatMap(\.expected)))
        }
    }
}

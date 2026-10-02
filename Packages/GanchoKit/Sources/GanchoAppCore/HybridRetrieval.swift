import Foundation
import GanchoKit

public struct HybridSearchResult: Sendable, Equatable {
    public enum SemanticState: Sendable, Equatable { case notRequested, ready, unavailable }
    public let conventional: [ClipItem]
    public let related: [ClipItem]
    public let semanticState: SemanticState

    public var ordered: [ClipItem] { conventional + related }

    public init(
        conventional: [ClipItem], related: [ClipItem], semanticState: SemanticState
    ) {
        self.conventional = conventional
        var seen = Set(conventional.map(\.id))
        self.related = related.filter { seen.insert($0.id).inserted }
        self.semanticState = semanticState
    }
}

/// Metadata-only retrieval. Content reads and delivery remain separately authorized.
public struct HybridRetrieval: Sendable {
    public init() {}

    public func search(
        _ query: ClipSearchQuery, store: any ClipSearching & ScopedSemanticSearching,
        queryVector: [Float]?, conventionalLimit: Int = 100, relatedLimit: Int = 10
    ) async throws -> HybridSearchResult {
        try Task.checkCancellation()
        let conventional = try await store.search(query, limit: conventionalLimit)
        guard query.mode != .regex,
            !query.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let queryVector
        else {
            return HybridSearchResult(
                conventional: conventional, related: [], semanticState: .notRequested)
        }
        do {
            let related = try await store.semanticSearch(
                queryVector: queryVector, query: query, topK: relatedLimit, snippetsOnly: false)
            try Task.checkCancellation()
            // Re-run the ordinary predicates after the asynchronous vector query. A row
            // deleted or edited in the meantime must not retain an obsolete literal hit.
            var currentQuery = query
            currentQuery.includedIDs = Set(conventional.map(\.id))
            let current = try await store.search(currentQuery, limit: conventional.count)
            let currentByID = Dictionary(uniqueKeysWithValues: current.map { ($0.id, $0) })
            try Task.checkCancellation()
            return HybridSearchResult(
                conventional: conventional.compactMap { currentByID[$0.id] },
                related: related, semanticState: .ready)
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            let current = try await store.search(query, limit: conventionalLimit)
            try Task.checkCancellation()
            return HybridSearchResult(
                conventional: current, related: [], semanticState: .unavailable)
        }
    }
}

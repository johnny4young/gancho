import Foundation
import GanchoAI
import GanchoKit
import Observation

public struct MeaningSearchResponse: Sendable {
    public let items: [ClipItem]
    public let coverage: SemanticIndexCoverage
    public init(items: [ClipItem], coverage: SemanticIndexCoverage) {
        self.items = items
        self.coverage = coverage
    }
}

public enum MeaningSearchError: Error, Equatable { case unavailable, queryTooLong }

@MainActor public protocol MeaningSearchSource: AnyObject {
    func relatedItems(for query: ClipSearchQuery) async throws -> MeaningSearchResponse
}

/// Query embedding stays local and off the UI actor; no assets are requested or indexed.
public struct MeaningRetrieval: Sendable {
    public init() {}
    public func search(
        _ query: ClipSearchQuery, store: any ScopedSemanticSearching & SemanticIndexProviding
    ) async throws -> MeaningSearchResponse {
        try Task.checkCancellation()
        guard !query.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            query.mode != .regex
        else { throw MeaningSearchError.unavailable }
        guard query.text.utf8.count <= 4096, query.text.count <= 1000 else {
            throw MeaningSearchError.queryTooLong
        }
        let worker = Task.detached(priority: .userInitiated) { () throws -> [Float] in
            try Task.checkCancellation()
            guard let embedder = ContextualSentenceEmbedder(), embedder.hasAvailableAssets else {
                throw MeaningSearchError.unavailable
            }
            let vector = try embedder.vector(for: query.text)
            try Task.checkCancellation()
            return vector
        }
        let vector = try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
        try Task.checkCancellation()
        let coverage = try await store.semanticIndexCoverage(query: query, dimension: vector.count)
        let items = try await store.semanticSearch(
            queryVector: vector, query: query, topK: 10, snippetsOnly: false)
        try Task.checkCancellation()
        return MeaningSearchResponse(items: items, coverage: coverage)
    }
}

@MainActor @Observable public final class MeaningSearchState {
    public enum Status: Sendable, Equatable {
        case idle, loading, ready, incomplete, unavailable, queryTooLong
    }
    public private(set) var status: Status = .idle
    public private(set) var relatedIDs: Set<UUID> = []
    @ObservationIgnored private(set) var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    public init() {}

    public func invalidate() {
        cancelPending()
        relatedIDs = []
        status = .idle
    }

    public func cancelPending() {
        generation = UUID()
        task?.cancel()
        task = nil
        if status == .loading { status = .idle }
    }

    public func start(
        query: ClipSearchQuery, source: (any MeaningSearchSource)?,
        apply: @escaping @MainActor ([ClipItem]) -> [ClipItem]
    ) {
        invalidate()
        guard !query.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            query.mode != .regex
        else { return }
        guard let source else {
            status = .unavailable
            return
        }
        let request = generation
        status = .loading
        task = Task { [weak self] in
            do {
                let response = try await source.relatedItems(for: query)
                guard let self, !Task.isCancelled, generation == request else { return }
                relatedIDs = Set(apply(response.items).map(\.id))
                status = response.coverage.isComplete ? .ready : .incomplete
                task = nil
            } catch {
                guard let self, !Task.isCancelled, generation == request else { return }
                status =
                    (error as? MeaningSearchError) == .queryTooLong ? .queryTooLong : .unavailable
                task = nil
            }
        }
    }
}

import Foundation

/// Semantic retrieval with the same pre-limit metadata predicates as conventional search.
/// The query text is not an FTS constraint: callers provide its embedding separately.
public protocol ScopedSemanticSearching: Sendable {
    func semanticSearch(
        queryVector: [Float], query: ClipSearchQuery, topK: Int, snippetsOnly: Bool
    ) async throws -> [ClipItem]
}

extension GRDBClipboardStore: ScopedSemanticSearching {}

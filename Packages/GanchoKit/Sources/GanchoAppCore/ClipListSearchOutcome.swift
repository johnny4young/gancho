import Foundation
import GanchoKit

/// A successful empty search is distinct from a query that never completed.
public enum ClipListSearchOutcome: Sendable {
    case success([ClipItem])
    case failure(ClipSearchError)

    /// The shell supplies its store without constructing an app composition
    /// root. Both platforms share this content-free error classification.
    @MainActor public static func read(
        from store: (any ClipSearching)?, query: ClipSearchQuery, limit: Int
    ) async -> Self {
        await read {
            guard let store else { return [] }
            return try await store.search(query, limit: limit)
        }
    }

    @MainActor public static func read(
        _ operation: () async throws -> [ClipItem]
    ) async -> Self {
        guard !Task.isCancelled else { return .failure(.cancelled) }
        do {
            let items = try await operation()
            return Task.isCancelled ? .failure(.cancelled) : .success(items)
        } catch {
            if Task.isCancelled || error is CancellationError { return .failure(.cancelled) }
            return .failure((error as? ClipSearchError) ?? .readFailed)
        }
    }
}

extension ClipListSource {
    /// Compatibility for existing sources. Store-backed shells override this
    /// requirement so their throwing reads reach the typed boundary directly.
    public func searchOutcome(_ query: ClipSearchQuery, limit: Int) async -> ClipListSearchOutcome {
        let items = await search(query, limit: limit)
        return Task.isCancelled ? .failure(.cancelled) : .success(items)
    }
}

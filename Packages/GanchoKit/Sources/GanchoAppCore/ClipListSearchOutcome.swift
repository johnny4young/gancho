import Foundation
import GanchoKit

/// A successful empty search is distinct from a query that never completed.
public enum ClipListSearchOutcome: Sendable {
    case success([ClipItem])
    case failure(ClipSearchError)
    /// The caller's task was cancelled; nothing should be published.
    case cancelled

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

    /// A `CancellationError` from a task that was not cancelled is a failed read.
    @MainActor public static func read(
        _ operation: () async throws -> [ClipItem]
    ) async -> Self {
        guard !Task.isCancelled else { return .cancelled }
        do {
            let items = try await operation()
            return Task.isCancelled ? .cancelled : .success(items)
        } catch {
            if Task.isCancelled { return .cancelled }
            return .failure((error as? ClipSearchError) ?? .readFailed)
        }
    }
}

extension ClipListSource {
    /// Compatibility for existing sources. Store-backed shells override this
    /// requirement so their throwing reads reach the typed boundary directly.
    public func searchOutcome(_ query: ClipSearchQuery, limit: Int) async -> ClipListSearchOutcome {
        let items = await search(query, limit: limit)
        return Task.isCancelled ? .cancelled : .success(items)
    }
}

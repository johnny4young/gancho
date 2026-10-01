import GanchoAppCore
import GanchoKit

extension AppModel: MeaningSearchSource {
    func relatedItems(for query: ClipSearchQuery) async throws -> MeaningSearchResponse {
        #if DEBUG
            if CommandLine.arguments.contains("-ui-test-related-results"),
                CommandLine.arguments.contains("-use-temp-durable-store"),
                CommandLine.arguments.contains("-ui-test-defaults-suite"), let fullStore
            {
                var scoped = query
                scoped.text = ""
                scoped.excludesSensitive = true
                let items = try await fullStore.search(scoped, limit: 10)
                return MeaningSearchResponse(
                    items: items,
                    coverage: SemanticIndexCoverage(eligible: items.count + 1, indexed: items.count)
                )
            }
        #endif
        guard intelligence.semanticSearch, !preferences.isPrivateModePaused, let grdbForEngines
        else {
            throw MeaningSearchError.unavailable
        }
        let result = try await MeaningRetrieval().search(query, store: grdbForEngines)
        guard intelligence.semanticSearch, !preferences.isPrivateModePaused else {
            throw MeaningSearchError.unavailable
        }
        return result
    }
}

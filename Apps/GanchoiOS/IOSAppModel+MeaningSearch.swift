import Foundation
import GanchoAppCore
import GanchoKit

/// Related by meaning, on this iPhone's own index; nothing leaves the device.
extension IOSAppModel: MeaningSearchSource {
    func relatedItems(for query: ClipSearchQuery) async throws -> MeaningSearchResponse {
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-ui-test-related-results"),
                ProcessInfo.processInfo.arguments.contains("-use-temp-durable-store"), let full
            {
                var scoped = query
                scoped.text = ""
                scoped.excludesSensitive = true
                let items = try await full.search(scoped, limit: 10)
                return MeaningSearchResponse(
                    items: items,
                    coverage: SemanticIndexCoverage(eligible: items.count, indexed: items.count))
            }
        #endif
        guard intelligence.semanticSearch, let grdbForEngines else {
            throw MeaningSearchError.unavailable
        }
        let result = try await MeaningRetrieval().search(query, store: grdbForEngines)
        guard intelligence.semanticSearch else { throw MeaningSearchError.unavailable }
        return result
    }
}

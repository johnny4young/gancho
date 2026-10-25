import ClipboardCore
import Foundation
import GanchoAppCore
import GanchoKit

/// `AppModel` as the history panel's search data source. Search preserves
/// terminal errors for the panel. Legacy browse methods keep
/// their existing empty-list fallback.
/// `snippet(matchingKeyword:)` is already an `AppModel` method and satisfies the
/// requirement directly.
extension AppModel: PanelSearchSource {
    var isDurable: Bool { fullStore != nil }

    func recentBrowse(offset: Int, limit: Int) async -> [ClipItem] {
        guard let fullStore else { return await items(offset: offset, limit: limit) }
        return (try? await fullStore.recentForBrowse(offset: offset, limit: limit)) ?? []
    }

    func items(offset: Int, limit: Int) async -> [ClipItem] {
        (try? await store.items(offset: offset, limit: limit)) ?? []
    }

    func boardItems(_ boardID: UUID, offset: Int, limit: Int) async -> [ClipItem] {
        guard let fullStore else { return [] }
        return (try? await fullStore.items(inBoard: boardID, offset: offset, limit: limit)) ?? []
    }

    func search(_ query: ClipSearchQuery, limit: Int) async -> [ClipItem] {
        switch await searchOutcome(query, limit: limit) {
        case .success(let items): return items
        case .failure, .cancelled: return []
        }
    }

    func searchOutcome(_ query: ClipSearchQuery, limit: Int) async -> ClipListSearchOutcome {
        guard !Task.isCancelled else { return .cancelled }
        guard let fullStore else { return .success([]) }
        if !query.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            recordActivationMilestone(.firstSearch)
        }
        return await .read(from: fullStore, query: query, limit: limit)
    }

    func recentSourceApps(limit: Int) async -> [ClipSourceApp] {
        guard let fullStore else {
            let recent = (try? await store.items(offset: 0, limit: 200)) ?? []
            return ClipSourceAppDigest.from(recent, limit: limit)
        }
        return (try? await fullStore.recentSourceApps(limit: limit)) ?? []
    }

    func isDeletionPending(_ id: UUID) -> Bool { reuseController.isDeletionPending(id) }
}

import ClipboardCore
import Foundation
import GanchoAppCore
import GanchoKit

/// `AppModel` as the history panel's search data source. Each method wraps the
/// throwing store facets into the non-throwing shape `PanelSearchModel` expects
/// — a failed read degrades to an empty list, exactly as the panel did inline.
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
        guard let fullStore else { return [] }
        if !query.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            recordActivationMilestone(.firstSearch)
        }
        return (try? await fullStore.search(query, limit: limit)) ?? []
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

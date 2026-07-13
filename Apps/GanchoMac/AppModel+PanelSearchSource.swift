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
    var isDurable: Bool { grdbStore != nil }

    func recentBrowse(offset: Int, limit: Int) async -> [ClipItem] {
        guard let grdbStore else { return await items(offset: offset, limit: limit) }
        return (try? await grdbStore.recentForBrowse(offset: offset, limit: limit)) ?? []
    }

    func items(offset: Int, limit: Int) async -> [ClipItem] {
        (try? await store.items(offset: offset, limit: limit)) ?? []
    }

    func boardItems(_ boardID: UUID) async -> [ClipItem] {
        guard let grdbStore else { return [] }
        return (try? await grdbStore.items(inBoard: boardID)) ?? []
    }

    func search(_ query: ClipSearchQuery, limit: Int) async -> [ClipItem] {
        guard let grdbStore else { return [] }
        return (try? await grdbStore.search(query, limit: limit)) ?? []
    }

    func isDeletionPending(_ id: UUID) -> Bool { reuseController.isDeletionPending(id) }
}

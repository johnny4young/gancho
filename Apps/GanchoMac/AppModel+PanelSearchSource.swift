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

    func boardItems(_ boardID: UUID, offset: Int, limit: Int) async -> [ClipItem] {
        guard let grdbStore else { return [] }
        return (try? await grdbStore.items(inBoard: boardID, offset: offset, limit: limit)) ?? []
    }

    func search(_ query: ClipSearchQuery, limit: Int) async -> [ClipItem] {
        guard let grdbStore else { return [] }
        return (try? await grdbStore.search(query, limit: limit)) ?? []
    }

    func recentSourceApps(limit: Int) async -> [ClipSourceApp] {
        guard let grdbStore else {
            let recent = (try? await store.items(offset: 0, limit: 200)) ?? []
            return Self.sourceApps(from: recent, limit: limit)
        }
        return (try? await grdbStore.recentSourceApps(limit: limit)) ?? []
    }

    nonisolated private static func sourceApps(
        from items: [ClipItem], limit: Int
    ) -> [ClipSourceApp] {
        var counts: [String: Int] = [:]
        var order: [String] = []
        for item in items {
            guard let bundleID = item.sourceAppBundleID, !bundleID.isEmpty else { continue }
            if counts[bundleID] == nil { order.append(bundleID) }
            counts[bundleID, default: 0] += 1
        }
        return order.prefix(limit).map {
            ClipSourceApp(bundleID: $0, clipCount: counts[$0, default: 0])
        }
    }

    func isDeletionPending(_ id: UUID) -> Bool { reuseController.isDeletionPending(id) }
}

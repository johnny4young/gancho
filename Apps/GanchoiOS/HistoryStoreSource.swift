import ClipboardCore
import Foundation
import GanchoAppCore
import GanchoKit

/// Backs `HistoryListViewModel` with the iOS app's store handles. A dedicated
/// adapter (rather than making `IOSAppModel` the source) keeps the view model
/// free of a retain cycle back to the app model, and wraps the throwing store
/// facets into the non-throwing shape the list model expects — a failed read
/// degrades to an empty list, exactly as `IOSAppModel` did inline.
@MainActor final class HistoryStoreSource: HistoryListSource {
    private let store: any ClipboardStore
    private let full: (any FullClipStore)?

    init(store: any ClipboardStore, full: (any FullClipStore)?) {
        self.store = store
        self.full = full
    }

    var isDurable: Bool { full != nil }

    func recentBrowse(offset: Int, limit: Int) async -> [ClipItem] {
        guard let full else { return await items(offset: offset, limit: limit) }
        return (try? await full.recentForBrowse(offset: offset, limit: limit)) ?? []
    }

    func items(offset: Int, limit: Int) async -> [ClipItem] {
        (try? await store.items(offset: offset, limit: limit)) ?? []
    }

    func boardItems(_ boardID: UUID, offset: Int, limit: Int) async -> [ClipItem] {
        guard let full else { return [] }
        return (try? await full.items(inBoard: boardID, offset: offset, limit: limit)) ?? []
    }

    func search(_ query: ClipSearchQuery, limit: Int) async -> [ClipItem] {
        guard let full else { return [] }
        return (try? await full.search(query, limit: limit)) ?? []
    }

    func recentSourceApps(limit: Int) async -> [ClipSourceApp] {
        guard let full else {
            let recent = (try? await store.items(offset: 0, limit: 200)) ?? []
            return Self.sourceApps(from: recent, limit: limit)
        }
        return (try? await full.recentSourceApps(limit: limit)) ?? []
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
}

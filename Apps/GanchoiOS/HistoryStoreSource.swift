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

    func boardItems(_ boardID: UUID) async -> [ClipItem] {
        guard let full else { return [] }
        return (try? await full.items(inBoard: boardID)) ?? []
    }

    func search(_ query: ClipSearchQuery, limit: Int) async -> [ClipItem] {
        guard let full else { return [] }
        return (try? await full.search(query, limit: limit)) ?? []
    }
}

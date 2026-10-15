import GanchoAppCore
import GanchoKit

extension AppModel {
    func fetchLibraryClips(
        scope: LibraryClipScope, offset: Int, limit: Int
    ) async throws -> [ClipItem] {
        switch scope {
        case .allClips, .pinned:
            return try await store.items(offset: offset, limit: limit)
        case .board(let id):
            return try await fullStore?.items(inBoard: id, offset: offset, limit: limit) ?? []
        case .savedFilter(let rule):
            return try await fullStore?.items(matching: rule, limit: limit) ?? []
        }
    }
}

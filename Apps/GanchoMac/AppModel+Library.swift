import GanchoAppCore
import GanchoKit

extension AppModel {
    func snippetBody(for snippet: ClipItem) async -> String? {
        guard let reader = fullStore else { return nil }
        let body = await SnippetBodyLoader().load(
            snippet,
            metadata: { id in try await reader.item(id: id) },
            content: { id in try await reader.content(for: id) })
        if body == nil, !Task.isCancelled {
            toasts.show(
                GanchoToast(message: "Couldn’t insert this snippet. Open it again and try."))
        }
        return body
    }

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

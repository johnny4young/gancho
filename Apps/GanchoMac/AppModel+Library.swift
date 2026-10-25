import Foundation
import GanchoAppCore
import GanchoKit

extension AppModel {
    func snippetBody(for snippet: ClipItem) async -> String? {
        guard let reader = fullStore else { return nil }
        let body = await SnippetBodyLoader().load(
            snippet,
            metadata: { id in try await reader.item(id: id) },
            content: { id in try await reader.content(for: id) })
        if body == nil, !Task.isCancelled { reportSnippetUnavailable() }
        return body
    }

    func reportSnippetUnavailable() {
        toasts.show(GanchoToast(message: "Couldn’t insert this snippet. Open it again and try."))
    }

    func fetchLibraryClips(
        _ request: LibraryListRequest, offset: Int, limit: Int
    ) async throws -> [ClipItem] {
        guard let fullStore else {
            return try await fallbackLibraryClips(request, offset: offset, limit: limit)
        }
        if case .savedFilter(let rule) = request.scope {
            return try await fullStore.items(matching: rule, limit: limit)
        }
        let kinds = request.kind.kinds
        if !request.searchText.isEmpty {
            var query = ClipSearchQuery(text: request.searchText, kinds: kinds)
            switch request.scope {
            case .pinned: query.pinnedOnly = true
            case .board(let id): query.boardID = id
            case .allClips, .savedFilter: break
            }
            return try await fullStore.search(query, limit: limit)
        }
        guard let browse = Self.browseQuery(request) else { return [] }
        return try await fullStore.libraryItems(browse, offset: offset, limit: limit)
    }

    private func fallbackLibraryClips(
        _ request: LibraryListRequest, offset: Int, limit: Int
    ) async throws -> [ClipItem] {
        guard limit > 0 else { return [] }
        // The fallback owns no board memberships or persisted filters.
        switch request.scope {
        case .board, .savedFilter: return []
        case .allClips, .pinned: break
        }
        // A filtered raw page can look like EOF while older matches remain.
        // Read one RAM metadata snapshot, then apply the request before slicing.
        let snapshot = try await store.items(offset: 0, limit: Int.max)
        let matches = snapshot.filter {
            request.kind.matches($0.kind)
                && (request.scope != .pinned || $0.isPinned)
                && (request.searchText.isEmpty
                    || LibraryOrdering.matches($0, text: request.searchText))
        }
        let ordered = LibraryOrdering.sorted(matches, oldestFirst: request.oldestFirst)
        return Array(ordered.dropFirst(max(0, offset)).prefix(limit))
    }

    func countLibraryClips(_ request: LibraryListRequest) async throws -> Int {
        guard let fullStore, let browse = Self.browseQuery(request) else {
            throw CancellationError()
        }
        return try await fullStore.libraryCount(browse)
    }

    /// Board membership for the cards on screen, in one read.
    func libraryMembership(for clips: [ClipItem]) async -> [UUID: Set<UUID>] {
        guard let fullStore else { return [:] }
        return (try? await fullStore.boardIDs(forClips: clips.map(\.id))) ?? [:]
    }

    /// How many clips each saved filter holds; a filter that can't be read is left out.
    func savedFilterCounts(_ rules: [SmartCollectionRule]) async -> [UUID: Int] {
        guard let fullStore else { return [:] }
        var counts: [UUID: Int] = [:]
        for rule in rules {
            if let count = try? await fullStore.count(matching: rule) { counts[rule.id] = count }
        }
        return counts
    }

    private static func browseQuery(_ request: LibraryListRequest) -> LibraryBrowseQuery? {
        let scope: LibraryBrowseQuery.Scope
        switch request.scope {
        case .allClips: scope = .all
        case .pinned: scope = .pinned
        case .board(let id): scope = .board(id)
        case .savedFilter: return nil
        }
        return LibraryBrowseQuery(
            scope: scope, kinds: request.kind.kinds, oldestFirst: request.oldestFirst)
    }
}

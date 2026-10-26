import Foundation
import GanchoKit
import Observation

public enum LibraryClipScope: Sendable, Equatable {
    case allClips, pinned
    case board(UUID)
    case savedFilter(SmartCollectionRule)
}

/// What the Library shows: a sidebar scope narrowed by the search field, a
/// kind chip and the sort. Plain scopes page; a search or a saved filter loads
/// in one bounded read and is ordered here, so every list groups by date.
public struct LibraryListRequest: Sendable, Equatable {
    public var scope: LibraryClipScope
    public var text: String
    public var kind: ClipKindFilter
    public var oldestFirst: Bool

    public init(
        scope: LibraryClipScope, text: String = "", kind: ClipKindFilter = .all,
        oldestFirst: Bool = false
    ) {
        self.scope = scope
        self.text = text
        self.kind = kind
        self.oldestFirst = oldestFirst
    }

    public var searchText: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    public var isPaged: Bool {
        if case .savedFilter = scope { return false }
        return searchText.isEmpty
    }

    /// The one-shot read's limit: a text match is ranked, so fewer rows matter.
    var oneShotLimit: Int {
        let ruleText: String
        if case .savedFilter(let rule) = scope {
            ruleText = rule.textContains ?? ""
        } else {
            ruleText = ""
        }
        return searchText.isEmpty && ruleText.isEmpty ? 500 : 100
    }
}

extension LibraryListRequest {
    /// The page the in-memory fallback shows. It has no query engine, so the
    /// whole snapshot is narrowed before slicing; filtering a raw page would
    /// hide older matches and report a false end. Boards and saved filters
    /// live only in the durable store, so they read nothing.
    public func fallbackPage(
        offset: Int, limit: Int, snapshot: () async throws -> [ClipItem]
    ) async rethrows -> [ClipItem] {
        guard limit > 0 else { return [] }
        switch scope {
        case .board, .savedFilter: return []
        case .allClips, .pinned: break
        }
        let text = searchText
        let matches = try await snapshot().filter {
            kind.matches($0.kind)
                && (scope != .pinned || $0.isPinned)
                && (text.isEmpty || LibraryOrdering.matches($0, text: text))
        }
        return Array(
            LibraryOrdering.sorted(matches, oldestFirst: oldestFirst)
                .dropFirst(max(0, offset)).prefix(limit))
    }
}

public enum LibraryOrdering {
    /// Pinned first, then by capture time, in the request's direction; the
    /// id breaks ties so equal timestamps keep one order.
    public static func sorted(_ items: [ClipItem], oldestFirst: Bool) -> [ClipItem] {
        items.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            if lhs.createdAt != rhs.createdAt {
                return oldestFirst ? lhs.createdAt < rhs.createdAt : lhs.createdAt > rhs.createdAt
            }
            return oldestFirst
                ? lhs.id.uuidString < rhs.id.uuidString : lhs.id.uuidString > rhs.id.uuidString
        }
    }

    /// Whether a clip's title or preview holds every word of `text`, ignoring
    /// case and accents: how a search narrows a saved filter's rows.
    public static func matches(_ item: ClipItem, text: String) -> Bool {
        let haystack = item.title + " " + item.preview
        return text.split(whereSeparator: \.isWhitespace).allSatisfy {
            haystack.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil
        }
    }
}

/// Owns the Library's browse requests, independently from the snippet draft.
/// Reloads retain the loaded window; cancelled or superseded reads cannot
/// publish rows, claim EOF, or dismiss a newer request's loading state.
@MainActor @Observable public final class LibraryClipListModel {
    public enum Failure: Sendable, Equatable { case unavailable, invalidFilter }
    public typealias Fetch = @MainActor (LibraryListRequest, Int, Int) async throws -> [ClipItem]
    public typealias Count = @MainActor (LibraryListRequest) async throws -> Int

    public private(set) var items: [ClipItem] = []
    public private(set) var request = LibraryListRequest(scope: .allClips)
    public var scope: LibraryClipScope { request.scope }
    /// Every clip the request matches, not just the loaded window; nil until known.
    public private(set) var total: Int?
    public private(set) var isLoading = false
    public private(set) var reachedEnd = false
    public private(set) var failure: Failure?
    @ObservationIgnored private let fetch: Fetch
    @ObservationIgnored private let count: Count?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var failedPage = false
    @ObservationIgnored private var reloadRequest: UUID?
    /// The last visible card asks for a page once; one that arrives mid-refresh waits for it.
    @ObservationIgnored private var pageAwaitingReload = false

    public init(fetch: @escaping Fetch, count: Count? = nil) {
        self.fetch = fetch
        self.count = count
    }

    public func cancel() {
        supersede()
        pageAwaitingReload = false
    }

    private func supersede() {
        generation = UUID()
        isLoading = false
    }

    /// Keeps the current search, kind and sort.
    public func reload(_ scope: LibraryClipScope, preservingWindow: Bool = false) async {
        var next = request
        next.scope = scope
        await reload(next, preservingWindow: preservingWindow)
    }

    public func reload(_ next: LibraryListRequest, preservingWindow: Bool = false) async {
        guard !Task.isCancelled else { return }
        let preserve = preservingWindow && next == self.request
        let size = preserve ? max(items.count, LibraryPager.pageSize) : LibraryPager.pageSize
        supersede()
        let request = generation
        // Only a refresh of the visible scope can owe its last card a page.
        reloadRequest = preserve ? request : nil
        if !preserve { pageAwaitingReload = false }
        if next != self.request { total = nil }
        self.request = next
        failure = nil
        failedPage = false
        reachedEnd = false
        if !preserve { items = [] }
        isLoading = true
        defer { if generation == request { isLoading = false } }
        guard next.isPaged else {
            await loadOnce(next, request: request)
            return
        }
        let outcome = await page(loaded: [], size: size, request: next)
        apply(outcome, request: request)
        await loadTotal(next, request: request)
        guard generation == request, pageAwaitingReload, !Task.isCancelled else { return }
        pageAwaitingReload = false
        guard failure == nil else { return }
        isLoading = false
        await loadMore()
    }

    public func loadMore() async {
        guard !Task.isCancelled, !reachedEnd else { return }
        guard !isLoading else {
            if reloadRequest == generation { pageAwaitingReload = true }
            return
        }
        let request = UUID()
        generation = request
        isLoading = true
        failure = nil
        failedPage = true
        defer { if generation == request { isLoading = false } }
        let outcome = await page(loaded: items, size: LibraryPager.pageSize, request: self.request)
        apply(outcome, request: request)
    }

    public func retry() async {
        if failedPage {
            await loadMore()
        } else {
            await reload(request, preservingWindow: true)
        }
    }

    private func page(
        loaded: [ClipItem], size: Int, request: LibraryListRequest
    ) async -> LibraryPager.Outcome {
        await LibraryPager.nextPage(
            loaded: loaded, pageSize: size,
            stopAt: request.scope == .pinned ? { !$0.isPinned } : nil
        ) { offset, limit in
            try await self.fetch(request, offset, limit)
        }
    }

    private func loadTotal(_ next: LibraryListRequest, request: UUID) async {
        guard generation == request, failure == nil, !Task.isCancelled else { return }
        guard let count else {
            total = reachedEnd ? items.count : nil
            return
        }
        let value = try? await count(next)
        guard generation == request, !Task.isCancelled else { return }
        total = value ?? (reachedEnd ? items.count : nil)
    }

    private func apply(_ outcome: LibraryPager.Outcome, request: UUID) {
        guard generation == request, !Task.isCancelled else { return }
        switch outcome {
        case .loaded(let rows, let ended):
            items = rows
            reachedEnd = ended
        case .failed:
            failure = .unavailable
        }
    }

    private func loadOnce(_ next: LibraryListRequest, request: UUID) async {
        do {
            let rows = try await fetch(next, 0, next.oneShotLimit)
            guard generation == request, !Task.isCancelled else { return }
            var matches = rows.filter { next.kind.matches($0.kind) }
            if case .savedFilter = next.scope, !next.searchText.isEmpty {
                matches = matches.filter { LibraryOrdering.matches($0, text: next.searchText) }
            }
            items = LibraryOrdering.sorted(matches, oldestFirst: next.oldestFirst)
            total = items.count
            reachedEnd = true
        } catch {
            guard generation == request, !Task.isCancelled else { return }
            failure =
                error is SavedFilterError || error is ClipSearchError
                ? .invalidFilter : .unavailable
            reachedEnd = true
        }
    }
}

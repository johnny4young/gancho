import ClipboardCore
import Foundation
import GanchoKit
import Observation

/// The data the history panel's search needs from the app shell. `AppModel`
/// conforms to it in production; tests pass an in-memory fake, which is the
/// whole point of the extraction — the search/pagination/grouping rules were
/// unreachable by `swift test` while they lived on the `PanelView` struct.
@MainActor public protocol PanelSearchSource: AnyObject {
    /// True when a durable (GRDB) store backs the app; false on the in-memory
    /// fallback, which has neither board queries nor ranked search.
    var isDurable: Bool { get }
    /// The recent list ordered for browsing (pins first, then capture time), so
    /// the date buckets stay contiguous and the cursor matches the visual order.
    func recentBrowse(offset: Int, limit: Int) async -> [ClipItem]
    /// The protocol store ordering — the in-memory fallback path and the source
    /// of the client-side `contains` search when no durable store is present.
    func items(offset: Int, limit: Int) async -> [ClipItem]
    /// A board's curated set (durable stores only).
    func boardItems(_ boardID: UUID) async -> [ClipItem]
    /// Ranked full-text search (durable stores only).
    func search(_ query: ClipSearchQuery, limit: Int) async -> [ClipItem]
    /// The snippet whose keyword matches the query exactly, if any.
    func snippet(matchingKeyword keyword: String) async -> ClipItem?
    /// Whether a clip's delete is in its undo window — such rows hide at once.
    func isDeletionPending(_ id: UUID) -> Bool
}

/// A contiguous run of clips in one section, tagged with the shared
/// `ClipSection` grouping (Pinned first, then date buckets) the iOS list uses.
public struct PanelDateGroup: Identifiable, Sendable {
    public let section: ClipSection
    public let rows: [(index: Int, item: ClipItem)]
    /// Identity is the SECTION, which is stable and unique per run (each section
    /// appears once, contiguously). Keying on the first clip's id instead made
    /// the group's identity change every time a new clip landed at the top —
    /// SwiftUI then reused the nested rows across the "new" group and never
    /// refreshed their global index, so several clips shared one ⌘N badge and
    /// the selection highlight landed on more than one row.
    public var id: ClipSection { section }
}

/// The macOS history panel's search + list state, lifted off the `PanelView`
/// struct so its logic (type/board filtering, de-dupe, incremental paging,
/// section grouping, selection) is `@Observable` and unit-testable. The view
/// keeps presentation only (focus, rails, peek text, sheets, ask).
@MainActor @Observable public final class PanelSearchModel {
    /// The live search field text. Empty shows the paginated recent list.
    public var query = ""
    /// The rows returned by the current query/board/recent load, pre-filter.
    public var results: [ClipItem] = []
    /// The keyboard/selection cursor into `filtered`.
    public var selectedIndex = 0
    /// Date-bucketed rows for the recent list, cached so the bucket math runs
    /// once per data change, never on the scroll/arrow path.
    public var groups: [PanelDateGroup] = []
    /// A page is in flight.
    public var isLoadingMore = false
    /// The store has no more rows to append.
    public var reachedEnd = false
    /// The active type-filter pill.
    public var kindFilter: ClipKindFilter = .all
    /// nil = "All clips"; otherwise the selected board's id.
    public var selectedBoardID: UUID?
    /// The snippet whose keyword the query matches exactly — surfaces a
    /// one-keystroke insert banner above the list.
    public var snippetMatch: ClipItem?

    private let source: any PanelSearchSource

    public init(source: any PanelSearchSource) {
        self.source = source
    }

    static let pageSize = 100
    static let prefetchThreshold = 20

    /// How much habit weighs against text relevance in search results. One
    /// tunable in one place: at 3.0, a clip pasted ~10 times yesterday outranks
    /// a slightly-better text match untouched for months.
    nonisolated static let frecencyWeight = 3.0

    /// Blends the store's BM25 order with per-clip frecency, in Swift — SQLite
    /// math functions (`ln`/`exp`) aren't guaranteed under the SQLCipher fork,
    /// and the store doesn't expose raw BM25 scores. The incoming position is
    /// the relevance proxy (`hits.count - index` preserves the FTS order among
    /// unused clips); frecency = ln(1+uses) decayed by ~30-day half-life over
    /// `lastUsedAt`. Applied to search results only, never the recent list.
    nonisolated static func reranked(_ hits: [ClipItem], now: Date = .now) -> [ClipItem] {
        hits.enumerated()
            .map { index, item -> (item: ClipItem, score: Double) in
                let bm25Proxy = Double(hits.count - index)
                let days =
                    item.lastUsedAt.map { max(0, now.timeIntervalSince($0)) / 86_400 } ?? 365
                let frecency = log(1 + Double(item.uses)) * exp(-days / 30)
                return (item, bm25Proxy + Self.frecencyWeight * frecency)
            }
            .sorted { $0.score > $1.score }
            .map(\.item)
    }

    /// The rows actually shown: `results` narrowed by the active filter pill,
    /// then DE-DUPED by id. Pagination overlap (or a capture landing mid-scroll)
    /// can put the same clip in `results` twice; duplicate `ForEach`/`.id` keys
    /// make SwiftUI's selection highlight land on several rows or none, so the
    /// list must never carry a repeated id. Also hides clips whose delete is in
    /// the undo window, so a deleted row disappears immediately (Undo brings it
    /// back) instead of lingering and reading as "not deleted".
    public var filtered: [ClipItem] {
        let base = kindFilter == .all ? results : results.filter { kindFilter.matches($0.kind) }
        var seen = Set<UUID>()
        return base.filter {
            seen.insert($0.id).inserted && !source.isDeletionPending($0.id)
        }
    }

    /// The row under the cursor, if any.
    public var selectedItem: ClipItem? {
        filtered.indices.contains(selectedIndex) ? filtered[selectedIndex] : nil
    }

    /// A type or board filter is narrowing the list — drives the no-results
    /// "Clear filters" affordance.
    public var hasActiveFilter: Bool { kindFilter != .all || selectedBoardID != nil }

    /// The recent list is showing (paginates); a query or board is a bounded set.
    public var isGroupedView: Bool { query.isEmpty && selectedBoardID == nil }

    /// Select a row by index (the click + arrow path).
    public func select(_ index: Int) { selectedIndex = index }

    /// Type-to-search: first keystroke already narrows; empty query shows
    /// recents (pins first, store order). The recent list paginates on demand.
    public func refresh() async {
        let board = selectedBoardID
        if query.isEmpty {
            if let board, source.isDurable {
                results = await source.boardItems(board)
                reachedEnd = true  // a board is a curated set — loaded whole
            } else {
                results = await loadRecentPage(offset: 0)
                reachedEnd = results.count < Self.pageSize
            }
        } else if source.isDurable {
            // Frecency re-rank applies to SEARCH ONLY: the recent list above
            // stays chronological (that's the mental model). Blending happens
            // here in Swift, not SQL — see `reranked`.
            results = Self.reranked(
                await source.search(
                    ClipSearchQuery(text: query, boardID: board), limit: 100))
            reachedEnd = true  // ranked top results, not a scroll-through
        } else {
            let all = await source.items(offset: 0, limit: 200)
            results = Self.reranked(
                all.filter { $0.preview.localizedCaseInsensitiveContains(query) })
            reachedEnd = true
        }
        // A query that exactly matches a snippet's keyword offers a one-keystroke
        // insert (filling {fields} first if it's a template).
        snippetMatch = query.isEmpty ? nil : await source.snippet(matchingKeyword: query)
        selectedIndex = 0
        rebuildGroups()
    }

    /// One page of the recent list, ordered by capture time so the date buckets
    /// stay contiguous. Falls back to the protocol ordering when no durable
    /// store is available (tests / in-memory).
    private func loadRecentPage(offset: Int) async -> [ClipItem] {
        if source.isDurable {
            return await source.recentBrowse(offset: offset, limit: Self.pageSize)
        }
        return await source.items(offset: offset, limit: Self.pageSize)
    }

    /// Append the next page when the displayed cursor/scroll nears the end. Safe
    /// to call often — it no-ops unless the recent list has more to load.
    public func loadMoreIfNeeded(_ index: Int) async {
        guard index >= filtered.count - Self.prefetchThreshold else { return }
        await loadMore()
    }

    public func loadMore() async {
        guard isGroupedView, !isLoadingMore, !reachedEnd else { return }
        let offset = results.count
        isLoadingMore = true
        defer { isLoadingMore = false }
        let next = await loadRecentPage(offset: offset)
        // The view may have changed during the await (query typed, board picked,
        // a fresh refresh); only append if still extending the same list.
        guard isGroupedView, results.count == offset else { return }
        results.append(contentsOf: next)
        if next.count < Self.pageSize { reachedEnd = true }
        rebuildGroups()
    }

    /// Recompute the sections for the recent list — pinned first, then date
    /// buckets. Called when the data or the kind filter changes (NOT per render),
    /// so the Calendar math over thousands of rows never lands on the scroll
    /// path. The query orders pinned-first then by capture time, so the sections
    /// come out contiguous in one linear pass.
    public func rebuildGroups() {
        guard isGroupedView else {
            if !groups.isEmpty { groups = [] }
            return
        }
        let now = Date()
        var built: [PanelDateGroup] = []
        var section: ClipSection?
        var rows: [(index: Int, item: ClipItem)] = []
        for (index, item) in filtered.enumerated() {
            let itemSection: ClipSection =
                item.isPinned ? .pinned : .date(DateBucket.of(item.createdAt, now: now))
            if itemSection != section {
                if let section { built.append(PanelDateGroup(section: section, rows: rows)) }
                section = itemSection
                rows = []
            }
            rows.append((index: index, item: item))
        }
        if let section { built.append(PanelDateGroup(section: section, rows: rows)) }
        groups = built
    }
}

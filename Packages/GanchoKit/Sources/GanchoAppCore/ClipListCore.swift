import ClipboardCore
import Foundation
import GanchoKit

/// What any clip list needs from its shell.
///
/// The intersection of what the macOS panel and the iOS history ask for.
/// `PanelSearchSource` adds the two hooks only macOS has (snippet keywords and
/// the undo-window deletion check); `HistoryListSource` is this and nothing
/// more. Kept as a real inheritance rather than defaulted requirements so a
/// macOS conformer still has to supply those hooks — a silent default for
/// "is this clip's delete pending" would hide a broken panel, not fix one.
@MainActor public protocol ClipListSource: AnyObject {
    /// True when a durable (GRDB) store backs the app; false on the in-memory
    /// fallback, which has neither board queries nor ranked search.
    var isDurable: Bool { get }
    /// The recent list ordered for browsing (pins first, then capture time), so
    /// the date buckets stay contiguous and any cursor matches visual order.
    func recentBrowse(offset: Int, limit: Int) async -> [ClipItem]
    /// The protocol store ordering — the in-memory fallback path and the source
    /// of the client-side `contains` search when no durable store is present.
    func items(offset: Int, limit: Int) async -> [ClipItem]
    /// One page of a board's curated set (durable stores only).
    func boardItems(_ boardID: UUID, offset: Int, limit: Int) async -> [ClipItem]
    /// Ranked full-text search (durable stores only; [] otherwise).
    func search(_ query: ClipSearchQuery, limit: Int) async -> [ClipItem]
    /// Content-free source-app options for the filter menu.
    func recentSourceApps(limit: Int) async -> [ClipSourceApp]
}

/// Where the two shells genuinely differ, and nowhere else.
///
/// Only two fields, because only two things actually diverge. Values the
/// shells share — page size, the browsing ceiling, the fallback scan — are
/// constants on ``ClipListCore`` instead: making them configurable would
/// invent a knob nobody turns, and a knob nobody turns is a knob that drifts
/// away from its only real value.
///
/// Divergence in PRESENTATION stays in the adapters (macOS de-dupes and hides
/// pending deletions, iOS does not; macOS groups into indexed rows, iOS into
/// `ClipSectionGroup`), because none of that is loading.
public struct ClipListConfiguration: Sendable {
    /// Ranked-search ceiling once the user has typed something. macOS shows
    /// 100, iOS 50 — a real, pre-existing difference that used to be a literal
    /// buried in each model.
    public var searchLimitWithQuery: Int
    /// Blend habit into SEARCH results. macOS does; iOS does not, and the
    /// recent list never does on either — chronological is the mental model.
    public var rerankSearchByFrecency: Bool

    public init(searchLimitWithQuery: Int, rerankSearchByFrecency: Bool) {
        self.searchLimitWithQuery = searchLimitWithQuery
        self.rerankSearchByFrecency = rerankSearchByFrecency
    }

    public static let macOSPanel = ClipListConfiguration(
        searchLimitWithQuery: 100, rerankSearchByFrecency: true)

    public static let iOSHistory = ClipListConfiguration(
        searchLimitWithQuery: 50, rerankSearchByFrecency: false)
}

/// One load's worth of rows, plus whether the store has more.
public struct ClipListPage: Sendable, Equatable {
    public var items: [ClipItem]
    /// No further page exists — either the store returned a short page, or this
    /// view does not paginate at all (a ranked search is a bounded top-N).
    public var reachedEnd: Bool

    public init(items: [ClipItem], reachedEnd: Bool) {
        self.items = items
        self.reachedEnd = reachedEnd
    }
}

/// Which shape of list the current filters describe.
///
/// Both shells derived these from the same three fields with the same rules,
/// and a drift between them would be invisible: the list would simply stop
/// grouping, or start appending pages to a bounded result set.
public enum ClipListShape {
    /// The recent list — the only date-grouped view. Boards paginate too but
    /// render flat; a query is a bounded ranked set.
    public static func isGrouped(
        query: String, boardID: UUID?, sourceAppBundleID: String?
    ) -> Bool {
        query.isEmpty && boardID == nil && sourceAppBundleID == nil
    }

    /// The list appends pages on scroll: the recent browse or a board view.
    /// A query or source-app filter is a bounded top-N and never appends.
    public static func isPaginated(query: String, sourceAppBundleID: String?) -> Bool {
        query.isEmpty && sourceAppBundleID == nil
    }
}

/// The loading half of a clip list: which query to run, with what ceiling, and
/// how to page it.
///
/// Extracted because both shells had grown the same three-branch load — recent
/// or board, ranked search, in-memory fallback — and had already drifted in the
/// places a reader would least expect (search ceilings, whether the kind filter
/// reaches SQL). Divergence that is deliberate now lives in
/// ``ClipListConfiguration`` where it can be read at a glance; divergence that
/// was accidental is gone.
///
/// Deliberately holds no list state. The models keep their own rows, caches and
/// selection, so this stays a pure function of its arguments and each shell's
/// staleness guard can go on reading the state only that shell has.
@MainActor public struct ClipListCore {
    /// Rows per page for the recent list and for a board. Same on both shells.
    public static let pageSize = 100
    /// Ranked-search ceiling for a filter-only query (no text). Higher than the
    /// typed-query ceiling on purpose: the user is browsing a filter, not
    /// homing in on a phrase. Same on both shells.
    public static let searchLimitWithoutQuery = 500
    /// How much of the store the non-durable path scans before filtering in
    /// Swift. Only the in-memory fallback takes this route. Same on both.
    public static let clientFallbackLimit = 200

    public let configuration: ClipListConfiguration
    private let source: any ClipListSource

    public init(source: any ClipListSource, configuration: ClipListConfiguration) {
        self.source = source
        self.configuration = configuration
    }

    /// The first page for the current filters.
    ///
    /// `kinds` reaches SQL only when the caller passes it. macOS narrows by kind
    /// on the client (its filter also feeds de-duplication and selection, which
    /// are client-side anyway) and passes nil; iOS pushes it down.
    public func firstPage(
        query: String, boardID: UUID?, sourceAppBundleID: String?,
        kinds: Set<ClipContentKind>? = nil
    ) async -> ClipListPage {
        if query.isEmpty, sourceAppBundleID == nil {
            if let boardID, source.isDurable {
                // A board pages like the recent list — a curated set is still
                // unbounded (a 10k-member board must not load whole on open).
                let items = await source.boardItems(
                    boardID, offset: 0, limit: Self.pageSize)
                return ClipListPage(
                    items: items, reachedEnd: items.count < Self.pageSize)
            }
            let items = await recentPage(offset: 0)
            return ClipListPage(items: items, reachedEnd: items.count < Self.pageSize)
        }

        if source.isDurable {
            let hits = await source.search(
                ClipSearchQuery(
                    text: query, kinds: kinds, sourceAppBundleID: sourceAppBundleID,
                    boardID: boardID),
                limit: query.isEmpty
                    ? Self.searchLimitWithoutQuery
                    : configuration.searchLimitWithQuery)
            // Ranked top results, not a scroll-through.
            return ClipListPage(items: ranked(hits), reachedEnd: true)
        }

        // No durable store: no FTS and no board queries, so scan a bounded slice
        // and narrow it in Swift. Tests and the in-memory fallback only.
        let all = await source.items(offset: 0, limit: Self.clientFallbackLimit)
        let filtered = all.filter {
            (query.isEmpty || $0.preview.localizedCaseInsensitiveContains(query))
                && (sourceAppBundleID == nil || $0.sourceAppBundleID == sourceAppBundleID)
        }
        return ClipListPage(items: ranked(filtered), reachedEnd: true)
    }

    /// The next page for an already-loaded paginated list.
    ///
    /// The caller re-checks its own state after this returns — the view can
    /// change during the await — so this deliberately reports only what the
    /// store said.
    public func nextPage(after offset: Int, boardID: UUID?) async -> ClipListPage {
        let items: [ClipItem]
        if let boardID, source.isDurable {
            items = await source.boardItems(boardID, offset: offset, limit: Self.pageSize)
        } else {
            items = await recentPage(offset: offset)
        }
        return ClipListPage(items: items, reachedEnd: items.count < Self.pageSize)
    }

    public func sourceApps(limit: Int) async -> [ClipSourceApp] {
        await source.recentSourceApps(limit: limit)
    }

    /// Pinned-first then capture time, so the date buckets stay contiguous.
    /// Falls back to the protocol ordering with no durable store.
    private func recentPage(offset: Int) async -> [ClipItem] {
        if source.isDurable {
            return await source.recentBrowse(offset: offset, limit: Self.pageSize)
        }
        return await source.items(offset: offset, limit: Self.pageSize)
    }

    private func ranked(_ hits: [ClipItem]) -> [ClipItem] {
        configuration.rerankSearchByFrecency ? FrecencyRanker.reranked(hits) : hits
    }
}

/// Blends the store's BM25 order with per-clip frecency.
///
/// In Swift, not SQL: SQLite math functions (`ln`/`exp`) are not guaranteed
/// under the SQLCipher fork, and the store does not expose raw BM25 scores.
/// Applied to search results only, never the recent list.
public enum FrecencyRanker {
    /// How much habit weighs against text relevance. One tunable in one place:
    /// at 3.0, a clip pasted ~10 times yesterday outranks a slightly-better
    /// text match untouched for months.
    nonisolated public static let weight = 3.0

    /// Habit score. A usage count without a timestamp is not a reliable
    /// recency signal, so it deliberately contributes nothing.
    nonisolated public static func score(for item: ClipItem, now: Date = .now) -> Double {
        guard let lastUsedAt = item.lastUsedAt else { return 0 }
        let days = max(0, now.timeIntervalSince(lastUsedAt)) / 86_400
        return log(1 + Double(item.uses)) * exp(-days / 30)
    }

    /// The incoming position is the relevance proxy — `hits.count - index`
    /// preserves the FTS order among clips with no usage history.
    nonisolated public static func reranked(_ hits: [ClipItem], now: Date = .now) -> [ClipItem] {
        hits.enumerated()
            .map { index, item -> (item: ClipItem, score: Double) in
                (item, Double(hits.count - index) + weight * score(for: item, now: now))
            }
            .sorted { $0.score > $1.score }
            .map(\.item)
    }
}

/// Derives the source-app menu from a slice of clips when no durable store can
/// answer the aggregate query.
///
/// Content-free by construction: it reads `sourceAppBundleID` and nothing else,
/// never a preview or a body. Both shells had this verbatim; one copy means one
/// place to keep that true.
public enum ClipSourceAppDigest {
    nonisolated public static func from(_ items: [ClipItem], limit: Int) -> [ClipSourceApp] {
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

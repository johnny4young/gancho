import ClipboardCore
import Foundation
import GanchoKit
import Observation

/// The data the iOS history list needs from the app shell. `IOSAppModel`
/// conforms to it in production; tests pass an in-memory fake. Mirrors
/// `PanelSearchSource` (macOS) minus the snippet/deletion hooks iOS doesn't use
/// because the two shells have different mutation and presentation contracts.
@MainActor public protocol HistoryListSource: AnyObject {
    /// True when a durable (GRDB) store backs the app; false on the in-memory
    /// fallback, which has neither board queries nor ranked search.
    var isDurable: Bool { get }
    /// The recent list ordered for browsing (pins first, then capture time).
    func recentBrowse(offset: Int, limit: Int) async -> [ClipItem]
    /// The protocol store ordering — the in-memory fallback path.
    func items(offset: Int, limit: Int) async -> [ClipItem]
    /// One page of a board's curated set (durable stores only).
    func boardItems(_ boardID: UUID, offset: Int, limit: Int) async -> [ClipItem]
    /// Ranked full-text search (durable stores only; [] otherwise).
    func search(_ query: ClipSearchQuery, limit: Int) async -> [ClipItem]
    /// Content-free source-app options for the filter menu.
    func recentSourceApps(limit: Int) async -> [ClipSourceApp]
}

/// The iOS history list's search + pagination + grouping state, lifted off
/// `IOSAppModel` so its logic is `@Observable` and unit-testable. `IOSAppModel`
/// owns one and forwards `captures`/`sections`/`query`/… to it, so the views are
/// unchanged. The iOS analog of macOS's `PanelSearchModel`.
@MainActor @Observable public final class HistoryListViewModel {
    /// Raw loaded clips (recent page(s), a board, or search results). The kind
    /// filter is applied on top via `visibleClips` so it never disturbs the
    /// pagination offset.
    public var captures: [ClipItem] = [] {
        didSet { rebuildVisible() }
    }
    /// Date-grouped sections (Pinned + Today/Yesterday/…) for the recent view.
    public var sections: [ClipSectionGroup] = []
    public var query = ""
    public var kindFilter: ClipContentKind? {
        didSet { rebuildVisible() }
    }
    /// nil = "All clips"; otherwise the selected board.
    public var selectedBoardID: UUID?
    /// nil = all apps; otherwise the source bundle identifier intersected with
    /// text, type, and board filters.
    public var selectedSourceAppBundleID: String?
    public var sourceApps: [ClipSourceApp] = []

    var reachedEnd = false
    var isLoadingMore = false
    static let pageSize = 100
    /// How close to the end an appearing row must be to pull the next page.
    static let loadMoreThreshold = 20

    private let source: any HistoryListSource

    public init(source: any HistoryListSource) {
        self.source = source
    }

    /// The recent list (no query, no board) is the only date-grouped view;
    /// boards paginate flat, search returns a bounded ranked set.
    public var isGroupedView: Bool {
        query.isEmpty && selectedBoardID == nil && selectedSourceAppBundleID == nil
    }

    /// The list appends pages on scroll: the recent browse or a board view.
    /// A query or source-app filter is a bounded top-N set and never appends.
    private var isPaginatedView: Bool {
        query.isEmpty && selectedSourceAppBundleID == nil
    }

    /// `captures` narrowed by the kind filter — what the list actually shows.
    ///
    /// Cached rather than computed: `loadMoreIfNeeded` runs once per row as the
    /// list scrolls, so deriving this on access allocated a filtered copy of
    /// the whole list for every row that appeared.
    public private(set) var visibleClips: [ClipItem] = []

    /// Ids of the last page-trigger rows, so the infinite-scroll guard is a set
    /// lookup instead of `firstIndex(where:)` — another full scan that ran per
    /// appearing row, on top of the copy.
    private var loadMoreTriggerIDs: Set<UUID> = []

    private func rebuildVisible() {
        visibleClips = kindFilter.map { kind in captures.filter { $0.kind == kind } } ?? captures
        loadMoreTriggerIDs = Set(visibleClips.suffix(Self.loadMoreThreshold).map(\.id))
    }

    /// Refreshes the app menu independently from text search so type-to-search
    /// does not repeat the aggregate metadata query on every keystroke.
    public func refreshSourceApps() async {
        sourceApps = await source.recentSourceApps(limit: 8)
    }

    public func search() async {
        let sourceApp = selectedSourceAppBundleID
        if query.isEmpty, sourceApp == nil {
            if let board = selectedBoardID, source.isDurable {
                // A board pages like the recent list — a curated set is still
                // unbounded (a 10k-member board must not load whole on open).
                captures = await source.boardItems(board, offset: 0, limit: Self.pageSize)
                reachedEnd = captures.count < Self.pageSize
            } else {
                captures = await loadRecentPage(offset: 0)
                reachedEnd = captures.count < Self.pageSize
            }
        } else if source.isDurable {
            let kinds: Set<ClipContentKind>? = kindFilter.map { [$0] }
            captures = await source.search(
                ClipSearchQuery(
                    text: query, kinds: kinds, sourceAppBundleID: sourceApp,
                    boardID: selectedBoardID),
                limit: query.isEmpty ? 500 : 50)
            reachedEnd = true
        } else {
            let all = await source.items(offset: 0, limit: 200)
            captures = all.filter {
                (query.isEmpty || $0.preview.localizedCaseInsensitiveContains(query))
                    && (sourceApp == nil || $0.sourceAppBundleID == sourceApp)
            }
            reachedEnd = true
        }
        rebuildSections()
    }

    /// Pinned-first then capture-time order, so the date buckets stay contiguous.
    private func loadRecentPage(offset: Int) async -> [ClipItem] {
        if source.isDurable {
            return await source.recentBrowse(offset: offset, limit: Self.pageSize)
        }
        return await source.items(offset: offset, limit: Self.pageSize)
    }

    /// Append the next page as the list nears its end (infinite scroll). No-ops
    /// unless the grouped recent view has more to load.
    public func loadMoreIfNeeded(_ item: ClipItem) async {
        guard isPaginatedView, !isLoadingMore, !reachedEnd,
            loadMoreTriggerIDs.contains(item.id)
        else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let board = selectedBoardID
        let offset = captures.count
        let next: [ClipItem]
        if let board, source.isDurable {
            next = await source.boardItems(board, offset: offset, limit: Self.pageSize)
        } else {
            next = await loadRecentPage(offset: offset)
        }
        // The view may have changed during the await (query typed, board picked
        // or switched); only append if still extending the same list.
        guard isPaginatedView, selectedBoardID == board, captures.count == offset else { return }
        captures.append(contentsOf: next)
        if next.count < Self.pageSize { reachedEnd = true }
        rebuildSections()
    }

    /// Rebuild the cached date sections — after a load, or when the kind filter
    /// changes (so the Calendar math never lands on the scroll path).
    public func rebuildSections() {
        rebuildVisible()
        sections = isGroupedView ? ClipSections.grouped(visibleClips, now: Date()) : []
    }
}

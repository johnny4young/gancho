import ClipboardCore
import Foundation
import GanchoKit
import Observation

/// The data the iOS history list needs from the app shell. `IOSAppModel`
/// conforms to it in production; tests pass an in-memory fake. Mirrors
/// `PanelSearchSource` (macOS) minus the snippet/deletion hooks iOS doesn't use
/// — kept separate rather than pre-abstracted (see `.audit/09` PR-I note).
@MainActor public protocol HistoryListSource: AnyObject {
    /// True when a durable (GRDB) store backs the app; false on the in-memory
    /// fallback, which has neither board queries nor ranked search.
    var isDurable: Bool { get }
    /// The recent list ordered for browsing (pins first, then capture time).
    func recentBrowse(offset: Int, limit: Int) async -> [ClipItem]
    /// The protocol store ordering — the in-memory fallback path.
    func items(offset: Int, limit: Int) async -> [ClipItem]
    /// A board's curated set (durable stores only).
    func boardItems(_ boardID: UUID) async -> [ClipItem]
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
    public var captures: [ClipItem] = []
    /// Date-grouped sections (Pinned + Today/Yesterday/…) for the recent view.
    public var sections: [ClipSectionGroup] = []
    public var query = ""
    public var kindFilter: ClipContentKind?
    /// nil = "All clips"; otherwise the selected board.
    public var selectedBoardID: UUID?
    /// nil = all apps; otherwise the source bundle identifier intersected with
    /// text, type, and board filters.
    public var selectedSourceAppBundleID: String?
    public var sourceApps: [ClipSourceApp] = []

    var reachedEnd = false
    var isLoadingMore = false
    static let pageSize = 100

    private let source: any HistoryListSource

    public init(source: any HistoryListSource) {
        self.source = source
    }

    /// The recent list (no query, no board) is the only date-grouped, paginated
    /// view; a board loads whole, search returns ranked results.
    public var isGroupedView: Bool {
        query.isEmpty && selectedBoardID == nil && selectedSourceAppBundleID == nil
    }

    /// `captures` narrowed by the kind filter — what the list actually shows.
    public var visibleClips: [ClipItem] {
        guard let kindFilter else { return captures }
        return captures.filter { $0.kind == kindFilter }
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
                captures = await source.boardItems(board)
                reachedEnd = true
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
        let visible = visibleClips
        guard isGroupedView, !isLoadingMore, !reachedEnd,
            let index = visible.firstIndex(where: { $0.id == item.id }),
            index >= visible.count - 20
        else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let offset = captures.count
        let next = await loadRecentPage(offset: offset)
        // The view may have changed during the await; only append if still
        // extending the same list.
        guard isGroupedView, captures.count == offset else { return }
        captures.append(contentsOf: next)
        if next.count < Self.pageSize { reachedEnd = true }
        rebuildSections()
    }

    /// Rebuild the cached date sections — after a load, or when the kind filter
    /// changes (so the Calendar math never lands on the scroll path).
    public func rebuildSections() {
        sections = isGroupedView ? ClipSections.grouped(visibleClips, now: Date()) : []
    }
}

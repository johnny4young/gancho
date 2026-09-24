import ClipboardCore
import Foundation
import GanchoKit
import Observation

/// The data the history panel's search needs from the app shell. `AppModel`
/// conforms to it in production; tests pass an in-memory fake, which is the
/// whole point of the extraction — the search/pagination/grouping rules were
/// unreachable by `swift test` while they lived on the `PanelView` struct.
@MainActor public protocol PanelSearchSource: ClipListSource {
    /// The snippet whose keyword matches the query exactly, if any. macOS only:
    /// the panel offers a one-keystroke insert, iOS has no equivalent surface.
    func snippet(matchingKeyword keyword: String) async -> ClipItem?
    /// Whether a clip's delete is in its undo window — such rows hide at once.
    /// macOS only: iOS deletes immediately, with no undo window to hide behind.
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
/// section grouping) is `@Observable` and unit-testable. Selection mutation is
/// delegated to `PanelSelectionModel`; the view keeps presentation only (focus,
/// rails, sheets, ask).
@MainActor @Observable public final class PanelSearchModel {
    /// The live search field text. Empty shows the paginated recent list.
    public var query = "" { didSet { if oldValue != query { invalidateRequests() } } }
    public var mode: ClipSearchQuery.Mode = .fuzzy {
        didSet { if oldValue != mode { invalidateRequests() } }
    }
    public var pinnedOnly = false {
        didSet { if oldValue != pinnedOnly { invalidateRequests() } }
    }
    private var refreshID = UUID()
    private var pageID: UUID?
    private var isRefreshing = false
    private var loadMoreDeferred = false
    private var displayedContext: Context?

    private struct Context: Equatable {
        let query: String
        let mode: ClipSearchQuery.Mode
        let kind: ClipKindFilter
        let pinnedOnly: Bool
        let boardID: UUID?
        let sourceApp: String?
    }

    private var context: Context {
        Context(
            query: query, mode: mode, kind: kindFilter, pinnedOnly: pinnedOnly,
            boardID: selectedBoardID, sourceApp: selectedSourceAppBundleID)
    }

    private func invalidateRequests() {
        refreshID = UUID()
        pageID = nil
        isLoadingMore = false
        isRefreshing = false
        loadMoreDeferred = false
        snippetMatch = nil
    }
    /// The rows returned by the current query/board/recent load, pre-filter.
    public var results: [ClipItem] = [] {
        didSet { rebuildVisible() }
    }
    /// Date-bucketed rows for the recent list, cached so the bucket math runs
    /// once per data change, never on the scroll/arrow path.
    public var groups: [PanelDateGroup] = []
    /// A page is in flight.
    public var isLoadingMore = false
    /// The store has no more rows to append.
    public var reachedEnd = false
    /// The active type-filter pill.
    public var kindFilter: ClipKindFilter = .all {
        didSet {
            if oldValue != kindFilter { invalidateRequests() }
            rebuildVisible()
        }
    }
    /// nil = "All clips"; otherwise the selected board's id.
    public var selectedBoardID: UUID? {
        didSet { if oldValue != selectedBoardID { invalidateRequests() } }
    }
    /// nil = all apps; otherwise the source bundle identifier to intersect with
    /// the current text, type, and board filters.
    public var selectedSourceAppBundleID: String? {
        didSet { if oldValue != selectedSourceAppBundleID { invalidateRequests() } }
    }
    /// Recent source apps and aggregate counts for the filter menu.
    public var sourceApps: [ClipSourceApp] = []
    /// The snippet whose keyword the query matches exactly — surfaces a
    /// one-keystroke insert banner above the list.
    public var snippetMatch: ClipItem?

    private let source: any PanelSearchSource
    private let core: ClipListCore
    private let selectionModel = PanelSelectionModel()

    public init(source: any PanelSearchSource) {
        self.source = source
        core = ClipListCore(source: source, configuration: .macOSPanel)
    }

    static let prefetchThreshold = 20

    /// The rows actually shown: `results` narrowed by the active filter pill,
    /// then DE-DUPED by id. Pagination overlap (or a capture landing mid-scroll)
    /// can put the same clip in `results` twice; duplicate `ForEach`/`.id` keys
    /// make SwiftUI's selection highlight land on several rows or none, so the
    /// list must never carry a repeated id. Also hides clips whose delete is in
    /// the undo window, so a deleted row disappears immediately (Undo brings it
    /// back) instead of lingering and reading as "not deleted".
    /// Cached, not computed. The selection accessors, the pagination guard and
    /// the group builder all read this, and the macOS row builder reads it once
    /// PER ROW through `selectedItems` — so computing it on access meant an
    /// O(n) filter and a fresh `Set` allocation for every visible row of every
    /// render, which is quadratic in a list that pages to thousands.
    ///
    /// Rebuilt when `results` or `kindFilter` change, and by
    /// ``reconcileVisible()`` when the pending-deletion set moves underneath it
    /// — that last one is why this is not simply derived state.
    public private(set) var filtered: [ClipItem] = []

    /// Recomputes ``filtered``.
    ///
    /// Order matters: dedupe before the pending check so a duplicated id cannot
    /// consume the `seen` slot and let its twin through. A repeated id makes
    /// SwiftUI's selection highlight land on several rows or none, which is
    /// what the dedupe is for; the pending check hides a clip whose delete is
    /// inside the undo window, so the row disappears the moment the user asks
    /// rather than lingering and reading as "not deleted".
    private func rebuildVisible() {
        let base = kindFilter == .all ? results : results.filter { kindFilter.matches($0.kind) }
        var seen = Set<UUID>()
        seen.reserveCapacity(base.count)
        filtered = base.filter {
            seen.insert($0.id).inserted && !source.isDeletionPending($0.id)
        }
        // Reconcile at replacement, not after a later snippet lookup. The
        // cursor follows its ID while surviving batch selections stay intact.
        selectionModel.reconcile(in: filtered)
    }

    /// Re-reads the pending-deletion set and rebuilds EVERY visible surface
    /// from it: the flat list, the date sections, and the selection.
    ///
    /// The shell calls this the instant the pending set changes — a delete or
    /// an undo — before the asynchronous refresh that follows. `pending` is
    /// state this model does not own, so nothing else would tell the caches
    /// they went stale, and waiting for the refresh would put a store round
    /// trip between the user's Delete and the row leaving the screen.
    ///
    /// Rebuilding `filtered` alone is not enough and was the bug this replaced:
    /// the recent list is the grouped view, and it renders ``groups``, so a
    /// deleted row stayed on screen in its cached section while `filtered`
    /// already knew it was gone.
    public func reconcileVisible() {
        rebuildGroups()
    }

    /// The keyboard/preview cursor into `filtered`. Plain assignments preserve
    /// the historical single-selection behavior by collapsing any batch.
    public var selectedIndex: Int {
        get { selectionModel.selectedIndex }
        set { selectionModel.select(newValue, toggling: false, in: filtered) }
    }

    /// The keyboard cursor and selected identifiers as a read-only snapshot.
    ///
    /// Mutate selection through `select`, `moveSelection`, `clearSelection`, or
    /// `reconcileSelection` so row reconciliation remains centralized.
    public var selection: PanelSelectionState { selectionModel.snapshot }

    /// The row under the cursor, if any.
    public var selectedItem: ClipItem? {
        selectionModel.selectedItem(in: filtered)
    }

    /// Selected clips in visible list order, never Set iteration order.
    public var selectedItems: [ClipItem] {
        selectionModel.selectedItems(in: filtered)
    }

    public var selectionCount: Int { selectionModel.selectionCount(in: filtered) }

    public func isSelected(_ id: UUID) -> Bool {
        selectionModel.isSelected(id)
    }

    /// A type or board filter is narrowing the list — drives the no-results
    /// "Clear filters" affordance.
    public var hasActiveFilter: Bool {
        kindFilter != .all || selectedBoardID != nil || selectedSourceAppBundleID != nil
            || pinnedOnly
    }

    /// The recent list is showing — the only date-grouped view. Boards
    /// paginate too but render flat; a query is a bounded ranked set.
    public var isGroupedView: Bool {
        kindFilter == .all && !pinnedOnly
            && ClipListShape.isGrouped(
                query: query, boardID: selectedBoardID,
                sourceAppBundleID: selectedSourceAppBundleID)
    }

    /// The list appends pages on scroll: the recent browse or a board view.
    /// A query or source-app filter is a bounded top-N set and never appends.
    private var isPaginatedView: Bool {
        kindFilter == .all && !pinnedOnly
            && ClipListShape.isPaginated(query: query, sourceAppBundleID: selectedSourceAppBundleID)
    }

    /// Refreshes app choices independently from text search so typing never
    /// repeats the aggregate query. Call on panel open and after history changes.
    public func refreshSourceApps() async {
        sourceApps = await core.sourceApps(limit: 8)
    }

    /// Select a row by index. Plain click replaces; Command-click toggles.
    public func select(_ index: Int, toggling: Bool = false) {
        selectionModel.select(index, toggling: toggling, in: filtered)
    }

    /// Shift-Up/Down grows or contracts a contiguous selection from its anchor.
    public func moveSelection(by delta: Int, extending: Bool) {
        selectionModel.move(by: delta, extending: extending, in: filtered)
    }

    /// Reconciles selection after deletion/filter changes without selecting a
    /// hidden id or leaving the cursor beyond the visible rows.
    public func reconcileSelection() {
        selectionModel.reconcile(in: filtered)
    }

    /// Leaves the cursor row selected and clears every additional row.
    public func clearSelection() {
        selectionModel.clear(in: filtered)
    }

    /// Type-to-search: first keystroke already narrows; empty query shows
    /// recents (pins first, store order). The recent list paginates on demand.
    public func refresh() async {
        let request = UUID()
        refreshID = request
        pageID = nil
        isLoadingMore = false
        isRefreshing = true
        let requestedContext = context
        defer { if refreshID == request { isRefreshing = false } }
        let page: ClipListPage
        if kindFilter != .all || pinnedOnly || mode != .fuzzy {
            let rule = savedRule(named: "")
            if source.isDurable {
                let items = await source.search(rule.query, limit: query.isEmpty ? 500 : 100)
                page = ClipListPage(items: FrecencyRanker.reranked(items), reachedEnd: true)
            } else {
                // `search` is durable-only (it answers [] on the in-memory
                // fallback), so a type or pin filter must narrow the scan
                // client-side, the way a typed query already does.
                page = await core.fallbackPage(matching: rule)
            }
        } else {
            page = await browsePage(request: request, requestedContext: requestedContext)
        }
        guard refreshID == request, context == requestedContext, !Task.isCancelled else { return }
        // A query that exactly matches a snippet's keyword offers a one-keystroke
        // insert (filling {fields} first if it's a template).
        let snippet =
            requestedContext.query.isEmpty
            ? nil : await source.snippet(matchingKeyword: requestedContext.query)
        guard refreshID == request, context == requestedContext, !Task.isCancelled else { return }
        let resetSelection = displayedContext != requestedContext
        results = page.items
        reachedEnd = page.reachedEnd
        snippetMatch = snippet
        displayedContext = requestedContext
        if resetSelection { selectedIndex = 0 }
        rebuildGroups()
        // A page requested while this refresh ran was deferred, not dropped.
        isRefreshing = false
        if loadMoreDeferred {
            loadMoreDeferred = false
            await loadMore()
        }
    }

    /// Refresh the already-loaded window, rather than dropping a cursor on a
    /// later page back into the first hundred rows: one read for the window,
    /// plus one page only when incoming rows pushed the selection past it.
    private func browsePage(request: UUID, requestedContext: Context) async -> ClipListPage {
        guard displayedContext == requestedContext, isPaginatedView else {
            return await core.firstPage(
                query: requestedContext.query, boardID: requestedContext.boardID,
                sourceAppBundleID: requestedContext.sourceApp)
        }
        let previousIDs = Set(results.map(\.id))
        var page = await core.leadingWindow(
            count: results.count, boardID: requestedContext.boardID)
        guard refreshID == request, !Task.isCancelled, !page.reachedEnd else { return page }
        let loadedIDs = Set(page.items.map(\.id))
        let shiftedSelection =
            !loadedIDs.isDisjoint(with: previousIDs)
            && !selection.selectedIDs.isSubset(of: loadedIDs)
        guard shiftedSelection else { return page }
        let next = await core.nextPage(after: page.items.count, boardID: requestedContext.boardID)
        page.items.append(contentsOf: next.items)
        page.reachedEnd = next.reachedEnd || next.items.isEmpty
        return page
    }

    public func savedRule(named name: String) -> SmartCollectionRule {
        SmartCollectionRule(
            name: name,
            kinds: kindFilter == .all
                ? nil : Set(ClipContentKind.allCases.filter(kindFilter.matches)),
            sourceAppBundleID: selectedSourceAppBundleID, textContains: query,
            pinnedOnly: pinnedOnly, boardID: selectedBoardID, searchMode: mode)
    }

    /// Append the next page when the displayed cursor/scroll nears the end. Safe
    /// to call often — it no-ops unless the recent list has more to load.
    public func loadMoreIfNeeded(_ index: Int) async {
        guard index >= filtered.count - Self.prefetchThreshold else { return }
        await loadMore()
    }

    public func loadMore() async {
        if isRefreshing, isPaginatedView {
            loadMoreDeferred = true
            return
        }
        guard isPaginatedView, displayedContext == context, !isLoadingMore, !reachedEnd
        else { return }
        let board = selectedBoardID
        let generation = refreshID
        let request = UUID()
        let offset = results.count
        pageID = request
        isLoadingMore = true
        defer {
            if pageID == request {
                pageID = nil
                isLoadingMore = false
            }
        }
        let page = await core.nextPage(after: offset, boardID: board)
        // The view may have changed during the await (query typed, board picked
        // or switched, a fresh refresh); only append if still extending the
        // same list. The guard stays here rather than in the core because it
        // reads state only this model has.
        guard refreshID == generation, pageID == request, !Task.isCancelled,
            isPaginatedView, selectedBoardID == board, results.count == offset
        else { return }
        results.append(contentsOf: page.items)
        if page.reachedEnd { reachedEnd = true }
        rebuildGroups()
    }

    /// Recompute the sections for the recent list — pinned first, then date
    /// buckets. Called when the data or the kind filter changes (NOT per render),
    /// so the Calendar math over thousands of rows never lands on the scroll
    /// path. The query orders pinned-first then by capture time, so the sections
    /// come out contiguous in one linear pass.
    public func rebuildGroups() {
        rebuildVisible()
        reconcileSelection()
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

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
    /// Clips first copied inside `range`, oldest first (durable stores only).
    func clipsCreated(in range: ClosedRange<Date>) async -> [ClipItem]
}

extension PanelSearchSource {
    public func clipsCreated(in range: ClosedRange<Date>) async -> [ClipItem] { [] }
}

/// A contiguous run of clips in one section, tagged with the shared
/// `ClipSection` grouping (Pinned first, then date buckets) the iOS list uses.
public struct PanelDateGroup: Identifiable, Sendable {
    public let section: ClipSection
    /// Rows resolve their cursor offset through
    /// ``PanelSearchModel/visibleIndex(of:)``, never a copy captured here.
    public let rows: [ClipItem]
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
    public let meaning = MeaningSearchState()
    public private(set) var searchFailure: ClipSearchError?
    public var meaningEnabled = false {
        didSet { if oldValue != meaningEnabled { invalidateRequests() } }
    }
    public func cancelMeaningSearch() { invalidateMeaningIntent() }

    /// The live search field text. Empty shows the paginated recent list.
    public var query = "" { didSet { if oldValue != query { invalidateRequests() } } }
    public var mode: ClipSearchQuery.Mode = .fuzzy {
        didSet { if oldValue != mode { invalidateRequests() } }
    }
    public var pinnedOnly = false {
        didSet { if oldValue != pinnedOnly { invalidateRequests() } }
    }
    /// The `device:` token: clips copied on this device only.
    public var deviceName: String? {
        didSet { if oldValue != deviceName { invalidateRequests() } }
    }
    /// The `before:` token: clips created before this instant only.
    public var createdBefore: Date? {
        didSet { if oldValue != createdBefore { invalidateRequests() } }
    }

    private var meaningIntent = UUID()
    private func invalidateMeaningIntent() {
        cancelPendingPaste()
        meaningIntent = UUID()
        meaning.cancelPending()
    }

    private var refreshID = UUID()
    private var pageID: UUID?
    private var isRefreshing = false
    public var isSearching: Bool { isRefreshing || (searchFailure == nil && !hasCurrentResults) }
    private var loadMoreDeferred = false
    private var displayedContext: Context?
    /// Retain context for selection and paging, but require a complete rows-and-snippet refresh.
    @ObservationIgnored private var displayedSnapshotIsValid = false
    /// Paste bookkeeping is read only by key actions, never rendered, so it
    /// stays out of observation: every arrow key regenerates the interaction.
    @ObservationIgnored private var pasteRequestID: UUID?
    /// Changes when input/navigation invalidates a key action, but not when
    /// its read finishes. The view uses this to coalesce only the same intent.
    @ObservationIgnored public private(set) var pasteInteractionID = UUID()

    private struct Context: Equatable {
        let query: String
        let mode: ClipSearchQuery.Mode
        let kind: ClipKindFilter
        let pinnedOnly: Bool
        let boardID: UUID?
        let sourceApp: String?
        let deviceName: String?
        let createdBefore: Date?
        let meaningOnly: Bool
    }

    private var context: Context {
        Context(
            query: query, mode: mode, kind: kindFilter, pinnedOnly: pinnedOnly,
            boardID: selectedBoardID, sourceApp: selectedSourceAppBundleID,
            deviceName: deviceName, createdBefore: createdBefore,
            meaningOnly: meaningEnabled && !query.isEmpty)
    }

    private func invalidateRequests() {
        dropContext()
        let relatedIDs = meaning.relatedIDs
        meaning.invalidate()
        if !relatedIDs.isEmpty { results.removeAll { relatedIDs.contains($0.id) } }
        invalidatePendingReads()
    }

    /// Keeps Meaning's related set so the next refresh can restore a selected related row.
    private func invalidatePendingReads() {
        cancelPendingPaste()
        displayedSnapshotIsValid = false
        searchFailure = nil
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
    @ObservationIgnored private var sourceAppsRequest = 0
    /// The snippet whose keyword the query matches exactly — surfaces a
    /// one-keystroke insert banner above the list.
    public var snippetMatch: ClipItem?

    let source: any PanelSearchSource
    private let core: ClipListCore
    private let selectionModel = PanelSelectionModel()

    public init(source: any PanelSearchSource) {
        self.source = source
        core = ClipListCore(source: source, configuration: .macOSPanel)
    }

    /// Requeries the active scope after a store mutation, independently of the
    /// shell's bounded recent page. Pending reads are invalidated before any
    /// await so an older request cannot restore a removed row.
    public func refreshAfterStoreChange() async {
        invalidatePendingReads()
        await refreshSourceApps()
        await refresh()
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
    private var visibleIndices: [UUID: Int] = [:]

    /// Resolve reused rows against the current list, never a captured pre-filter offset.
    public func visibleIndex(of id: UUID) -> Int? { visibleIndices[id] }

    /// Recomputes ``filtered``.
    ///
    /// Order matters: dedupe before the pending check so a duplicated id cannot
    /// consume the `seen` slot and let its twin through. A repeated id makes
    /// SwiftUI's selection highlight land on several rows or none, which is
    /// what the dedupe is for; the pending check hides a clip whose delete is
    /// inside the undo window, so the row disappears the moment the user asks
    /// rather than lingering and reading as "not deleted".
    private func rebuildVisible() {
        let base =
            kindFilter == .all || isShowingContext
            ? results : results.filter { kindFilter.matches($0.kind) }
        var seen = Set<UUID>()
        seen.reserveCapacity(base.count)
        filtered = base.filter {
            seen.insert($0.id).inserted && !source.isDeletionPending($0.id)
        }
        visibleIndices = Dictionary(
            uniqueKeysWithValues: filtered.enumerated().map { ($0.element.id, $0.offset) })
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

    /// The row the last arrow key moved up to, so the list can make room above
    /// it. A click clears it: scrolling under the pointer breaks a double click.
    public private(set) var upwardMoveTarget: UUID?

    /// The keyboard/preview cursor into `filtered`. Plain assignments preserve
    /// the historical single-selection behavior by collapsing any batch.
    public var selectedIndex: Int {
        get { selectionModel.selectedIndex }
        set {
            invalidateMeaningIntent()
            upwardMoveTarget = nil
            selectionModel.select(newValue, toggling: false, in: filtered)
        }
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

    /// A paste may only consume rows loaded for the live query and filters.
    public var hasCurrentResults: Bool { displayedSnapshotIsValid && displayedContext == context }

    /// Only identical repeated key actions coalesce. A different paste mode
    /// is a new intent even when the query and selection have not changed.
    public struct PasteRequestKey: Equatable, Sendable {
        public let interaction: UUID
        public let plain: Bool
        public let includingSnippet: Bool

        public init(interaction: UUID, plain: Bool, includingSnippet: Bool) {
            self.interaction = interaction
            self.plain = plain
            self.includingSnippet = includingSnippet
        }
    }

    public struct PasteTarget: Sendable {
        public let item: ClipItem
        public let isSnippet: Bool
    }

    /// Resolve an immediate Enter against the current search, rather than the
    /// previous rows still on screen. A later query, navigation, dismissal or
    /// paste request cancels this intent; no delayed paste survives it.
    public func resolvePasteTarget(
        includingSnippet: Bool, requestID: UUID? = nil
    ) async -> PasteTarget? {
        let request = requestID ?? beginPasteRequest()
        defer { if pasteRequestID == request { pasteRequestID = nil } }
        while !hasCurrentResults {
            guard pasteRequestID == request, !Task.isCancelled else { return nil }
            await refresh()
            if searchFailure != nil { return nil }
        }
        guard pasteRequestID == request, !Task.isCancelled else { return nil }
        if includingSnippet, let snippetMatch {
            return PasteTarget(item: snippetMatch, isSnippet: true)
        }
        guard let selectedItem else { return nil }
        return PasteTarget(item: selectedItem, isSnippet: false)
    }

    /// Capture the key action synchronously, before its Task gets scheduled.
    public func beginPasteRequest() -> UUID {
        let request = UUID()
        pasteRequestID = request
        return request
    }

    public func cancelPendingPaste() {
        pasteRequestID = nil
        pasteInteractionID = UUID()
    }

    public var selectionCount: Int { selectionModel.selectionCount(in: filtered) }

    public func isSelected(_ id: UUID) -> Bool {
        selectionModel.isSelected(id)
    }

    /// A type or board filter is narrowing the list — drives the no-results
    /// "Clear filters" affordance.
    public var hasActiveFilter: Bool {
        kindFilter != .all || selectedBoardID != nil || selectedSourceAppBundleID != nil
            || pinnedOnly || hasTokenOnlyFilter
    }

    /// Filters only tokens set; they bypass the grouped, paginated browse.
    private var hasTokenOnlyFilter: Bool { deviceName != nil || createdBefore != nil }

    /// The recent list is showing — the only date-grouped view. Boards
    /// paginate too but render flat; a query is a bounded ranked set.
    public var isGroupedView: Bool {
        !isShowingContext && kindFilter == .all && !pinnedOnly && !hasTokenOnlyFilter
            && ClipListShape.isGrouped(
                query: query, boardID: selectedBoardID,
                sourceAppBundleID: selectedSourceAppBundleID)
    }

    /// The list appends pages on scroll: the recent browse or a board view.
    /// A query or source-app filter is a bounded top-N set and never appends.
    private var isPaginatedView: Bool {
        !isShowingContext && kindFilter == .all && !pinnedOnly && !hasTokenOnlyFilter
            && ClipListShape.isPaginated(query: query, sourceAppBundleID: selectedSourceAppBundleID)
    }

    /// Select a row by index. Plain click replaces; Command-click toggles.
    public func select(_ index: Int, toggling: Bool = false) {
        invalidateMeaningIntent()
        upwardMoveTarget = nil
        selectionModel.select(index, toggling: toggling, in: filtered)
    }

    /// Opening the panel selects the first row (the first unpinned one without a
    /// query) and keeps it selected through refreshes until the user interacts.
    public func followNewestClip() {
        selectionModel.followNewest(skippingPinned: query.isEmpty, in: filtered)
    }

    public func endNewestFollow() {
        cancelPendingPaste()
        selectionModel.endNewestFollow()
    }

    /// Reconciles selection after deletion/filter changes without selecting a
    /// hidden id or leaving the cursor beyond the visible rows.
    public func reconcileSelection() {
        selectionModel.reconcile(in: filtered)
    }

    /// Leaves the cursor row selected and clears every additional row.
    public func clearSelection() {
        invalidateMeaningIntent()
        selectionModel.clear(in: filtered)
    }

    /// Type-to-search: first keystroke already narrows; empty query shows
    /// recents (pins first, store order). The recent list paginates on demand.
    public func refresh() async {
        if isShowingContext { return await refreshContext() }
        let intent = meaningIntent
        let priorSelection = displayedContext == context ? selectedItem?.id : nil
        let relatedSelection = priorSelection.flatMap { meaning.relatedIDs.contains($0) ? $0 : nil }
        meaning.cancelPending()
        let request = UUID()
        refreshID = request
        pageID = nil
        isLoadingMore = false
        isRefreshing = true
        let requestedContext = context
        defer { if refreshID == request { isRefreshing = false } }
        let page: ClipListPage
        if requestedContext.meaningOnly {
            // Meaning is its own mode: the related clips arrive from `startMeaning`.
            page = ClipListPage(items: [], reachedEnd: true)
        } else if kindFilter != .all || pinnedOnly || mode != .fuzzy || hasTokenOnlyFilter {
            let rule = savedRule(named: "")
            if source.isDurable {
                page = await core.searchPage(rule.query, limit: query.isEmpty ? 500 : 100)
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
        if let failure = page.searchFailure {
            failSearch(failure, for: requestedContext)
            return
        }
        searchFailure = nil
        // A query that exactly matches a snippet's keyword offers a one-keystroke
        // insert (filling {fields} first if it's a template).
        let snippet =
            requestedContext.query.isEmpty
            ? nil : await source.snippet(matchingKeyword: requestedContext.query)
        guard refreshID == request, context == requestedContext, !Task.isCancelled else { return }
        let resetSelection = displayedContext != requestedContext
        meaning.invalidate()
        selectionModel.resumeAutomaticSelection()
        if relatedSelection != nil, meaningIntent == intent {
            selectionModel.preserveEmptySelection()
        }
        results = page.items
        reachedEnd = page.reachedEnd
        snippetMatch = snippet
        displayedContext = requestedContext
        displayedSnapshotIsValid = true
        if resetSelection { selectionModel.select(0, toggling: false, in: filtered) }
        rebuildGroups()
        startMeaning(
            request: request, requestedContext: requestedContext, intent: intent,
            restoring: relatedSelection)
        // A page requested while this refresh ran was deferred, not dropped.
        isRefreshing = false
        if loadMoreDeferred {
            loadMoreDeferred = false
            await loadMore()
        }
    }

    private func failSearch(_ failure: ClipSearchError, for requestedContext: Context) {
        searchFailure = failure
        displayedSnapshotIsValid = false
        displayedContext = requestedContext
        loadMoreDeferred = false
        meaning.invalidate()
        results = []
        snippetMatch = nil
        reachedEnd = true
        rebuildGroups()
    }

    private func startMeaning(
        request: UUID, requestedContext: Context, intent: UUID, restoring selectedID: UUID?
    ) {
        guard meaningEnabled, meaningIntent == intent else { return }
        meaning.start(
            query: savedRule(named: "").query, source: source as? any MeaningSearchSource
        ) { [weak self] related in
            guard let self, refreshID == request, context == requestedContext, meaningEnabled,
                meaningIntent == intent
            else { return [] }
            let additions = HybridSearchResult(
                conventional: results, related: related, semanticState: .ready
            ).related
                .filter { !source.isDeletionPending($0.id) }
            let hadSelection = selectedItem != nil
            results.append(contentsOf: additions)
            if !hadSelection { selectionModel.preserveEmptySelection() }
            rebuildGroups()
            if let selectedID,
                let index = filtered.firstIndex(where: { $0.id == selectedID })
            {
                selectionModel.select(index, toggling: false, in: filtered)
            }
            return additions
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

    /// Jump to context; see the extension below.
    private var contextMode = PanelContextModeState()

    public func savedRule(named name: String) -> SmartCollectionRule {
        SmartCollectionRule(
            name: name,
            kinds: kindFilter == .all
                ? nil : Set(ClipContentKind.allCases.filter(kindFilter.matches)),
            sourceAppBundleID: selectedSourceAppBundleID, textContains: query,
            pinnedOnly: pinnedOnly, boardID: selectedBoardID, searchMode: mode,
            deviceName: deviceName, createdBefore: createdBefore)
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
        guard isGroupedView else {
            if !groups.isEmpty { groups = [] }
            return
        }
        let now = Date()
        var built: [PanelDateGroup] = []
        var section: ClipSection?
        var rows: [ClipItem] = []
        for item in filtered {
            let itemSection: ClipSection =
                item.isPinned ? .pinned : .date(DateBucket.of(item.createdAt, now: now))
            if itemSection != section {
                if let section { built.append(PanelDateGroup(section: section, rows: rows)) }
                section = itemSection
                rows = []
            }
            rows.append(item)
        }
        if let section { built.append(PanelDateGroup(section: section, rows: rows)) }
        groups = built
    }
}

// MARK: - Jump to context

private struct PanelContextModeState {
    var anchorID: UUID?
    var anchorDate = Date.distantPast
    var request: UUID?
    var saved: (results: [ClipItem], reachedEnd: Bool, snippet: ClipItem?)?
}

extension PanelSearchModel {
    /// Shift-Up/Down grows or contracts a contiguous selection from its anchor.
    public func moveSelection(by delta: Int, extending: Bool) {
        invalidateMeaningIntent()
        selectionModel.move(by: delta, extending: extending, in: filtered)
        upwardMoveTarget = delta < 0 ? selectedItem?.id : nil
    }

    /// An arrow key's move, as opposed to a click or a programmatic selection.
    public func moveCursor(to index: Int) {
        let movesUp = index < selectedIndex
        selectedIndex = index
        upwardMoveTarget = movesUp ? selectedItem?.id : nil
    }

    /// Refreshes app choices independently from text search so typing never
    /// repeats the aggregate query. Call on panel open and after history changes.
    /// Reads can overlap and answer out of order, so only the newest one lands.
    /// A cancelled or failed read keeps the list already showing.
    public func refreshSourceApps() async {
        sourceAppsRequest += 1
        let request = sourceAppsRequest
        guard let apps = try? await core.sourceApps(limit: 8), request == sourceAppsRequest
        else { return }
        sourceApps = apps
    }

    /// ±2 min around the anchor's first copy.
    public static let contextWindow: TimeInterval = 120
    /// The result the context list centers on; nil outside context mode.
    public var contextAnchorID: UUID? { contextMode.anchorID }
    public var isShowingContext: Bool { contextMode.anchorID != nil }

    /// Lists the clips first copied within ±2 min of the selected result.
    public func enterContext() async {
        guard !isShowingContext, hasCurrentResults, let anchor = selectedItem else { return }
        let request = UUID()
        contextMode.request = request
        let rows = await contextRows(around: anchor.createdAt, including: anchor)
        guard contextMode.request == request, !isShowingContext, hasCurrentResults,
            selectedItem?.id == anchor.id
        else { return }
        cancelPendingPaste()
        contextMode.saved = (results, reachedEnd, snippetMatch)
        contextMode.anchorID = anchor.id
        contextMode.anchorDate = anchor.createdAt
        snippetMatch = nil
        show(contextRows: rows, selecting: anchor.id)
    }

    /// Back to the results, on the row ⌘J was pressed on. The caller
    /// refreshes next, since the store may have changed meanwhile.
    public func exitContext() {
        guard let anchorID = contextAnchorID else { return }
        let saved = contextMode.saved
        dropContext()
        cancelPendingPaste()
        if let saved {
            results = saved.results
            reachedEnd = saved.reachedEnd
            snippetMatch = saved.snippet
        }
        displayedSnapshotIsValid = false
        rebuildGroups()
        if let index = filtered.firstIndex(where: { $0.id == anchorID }) {
            selectionModel.select(index, toggling: false, in: filtered)
        }
    }

    /// Any query or filter change leaves context mode for the new results.
    private func dropContext() {
        contextMode.anchorID = nil
        contextMode.request = nil
        contextMode.saved = nil
    }

    private func refreshContext() async {
        let request = UUID()
        contextMode.request = request
        let rows = await contextRows(around: contextMode.anchorDate, including: nil)
        guard contextMode.request == request, isShowingContext, !Task.isCancelled else { return }
        let selectedID = selectedItem?.id
        show(contextRows: rows, selecting: selectedID)
        displayedSnapshotIsValid = true
    }

    private func contextRows(around date: Date, including anchor: ClipItem?) async -> [ClipItem] {
        let window = Self.contextWindow
        var rows = await source.clipsCreated(
            in: date.addingTimeInterval(-window)...date.addingTimeInterval(window))
        // Without a durable store the anchor still shows, alone.
        if let anchor, !rows.contains(where: { $0.id == anchor.id }) {
            rows.append(anchor)
            rows.sort { $0.createdAt < $1.createdAt }
        }
        return rows
    }

    private func show(contextRows rows: [ClipItem], selecting id: UUID?) {
        results = rows
        reachedEnd = true
        rebuildGroups()
        let index = id.flatMap { id in filtered.firstIndex { $0.id == id } } ?? 0
        selectionModel.select(index, toggling: false, in: filtered)
    }
}

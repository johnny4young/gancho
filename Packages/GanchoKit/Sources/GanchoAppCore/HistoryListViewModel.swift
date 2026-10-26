import ClipboardCore
import Foundation
import GanchoKit
import Observation

/// The iOS history list needs exactly the shared surface and nothing more —
/// the snippet-keyword and pending-deletion hooks in `PanelSearchSource` are
/// macOS-only. A typealias rather than a second declaration so the two lists
/// cannot drift apart in what they ask a store for.
public typealias HistoryListSource = ClipListSource

/// The iOS history list's search + pagination + grouping state, lifted off
/// `IOSAppModel` so its logic is `@Observable` and unit-testable. `IOSAppModel`
/// owns one and forwards `captures`/`sections`/`query`/… to it, so the views are
/// unchanged. The iOS analog of macOS's `PanelSearchModel`.
@MainActor @Observable public final class HistoryListViewModel {
    public private(set) var searchFailure: ClipSearchError?
    public private(set) var isSearching = false
    /// Raw loaded clips (recent page(s), a board, or search results). The kind
    /// filter is applied on top via `visibleClips` so it never disturbs the
    /// pagination offset.
    public var captures: [ClipItem] = [] {
        didSet { rebuildVisible() }
    }
    /// Date-grouped sections (Pinned + Today/Yesterday/…) for the recent view.
    public var sections: [ClipSectionGroup] = []
    public var query = "" {
        didSet { if query != oldValue { requestChanged() } }
    }
    public var kindFilter: ClipContentKind? {
        didSet {
            if kindFilter != nil { kindGroup = .all }
            if kindFilter != oldValue { requestChanged() }
            rebuildSections()
        }
    }
    /// The iPad sidebar's type filter, a group of kinds. Picking one clears
    /// `kindFilter` and the other way round, so only one narrows the list.
    public var kindGroup: ClipKindFilter = .all {
        didSet {
            if kindGroup != .all { kindFilter = nil }
            if kindGroup != oldValue { requestChanged() }
            rebuildSections()
        }
    }
    /// The kinds the list keeps, nil for every kind.
    var activeKinds: Set<ClipContentKind>? {
        kindFilter.map { [$0] } ?? kindGroup.kinds
    }
    /// nil = "All clips"; otherwise the selected board.
    public var selectedBoardID: UUID? {
        didSet { if selectedBoardID != oldValue { requestChanged() } }
    }
    /// nil = all apps; otherwise the source bundle identifier intersected with
    /// text, type, and board filters.
    public var selectedSourceAppBundleID: String? {
        didSet { if selectedSourceAppBundleID != oldValue { requestChanged() } }
    }
    public var sourceApps: [ClipSourceApp] = []
    /// Clips related by meaning to the typed query, listed after the results
    /// and never repeating one of them.
    public let meaning = MeaningSearchState()
    private var relatedResults: [ClipItem] = []
    /// What the list shows as related: kept while a refresh of the same search
    /// re-runs it, dropped when the search failed or is unavailable.
    public var related: [ClipItem] {
        switch meaning.status {
        case .unavailable, .queryTooLong: []
        default: relatedResults
        }
    }
    /// The shell's on-device retrieval; nil leaves related results off.
    public weak var meaningSource: (any MeaningSearchSource)?

    var reachedEnd = false
    var isLoadingMore = false
    /// How close to the end an appearing row must be to pull the next page.
    static let loadMoreThreshold = 20

    private let core: ClipListCore

    public init(source: any HistoryListSource) {
        core = ClipListCore(source: source, configuration: .iOSHistory)
    }

    /// The recent list (no query, no board) is the only date-grouped view;
    /// boards paginate flat, search returns a bounded ranked set.
    public var isGroupedView: Bool {
        ClipListShape.isGrouped(
            query: query, boardID: selectedBoardID,
            sourceAppBundleID: selectedSourceAppBundleID)
    }

    /// The list appends pages on scroll: the recent browse or a board view.
    /// A query or source-app filter is a bounded top-N set and never appends.
    private var isPaginatedView: Bool {
        ClipListShape.isPaginated(query: query, sourceAppBundleID: selectedSourceAppBundleID)
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
        visibleClips =
            activeKinds.map { kinds in captures.filter { kinds.contains($0.kind) } } ?? captures
        loadMoreTriggerIDs = Set(visibleClips.suffix(Self.loadMoreThreshold).map(\.id))
    }

    /// Refreshes the app menu independently from text search so type-to-search
    /// does not repeat the aggregate metadata query on every keystroke.
    public func refreshSourceApps() async {
        sourceApps = await core.sourceApps(limit: 8)
    }

    /// Counts searches so an overlapping earlier one can never land after a
    /// newer one. A paste starts two: the hint refresh before the insert and
    /// the reload after it; if the first query answered last, it replaced the
    /// list with a page taken BEFORE the clip existed and the fresh clip
    /// vanished until the next refresh.
    private var searchGeneration = 0
    private var pageRequest: UUID?

    /// Both searches and pages belong to one request generation. An old page
    /// cannot append to a same-sized refresh or clear a newer page's spinner.
    /// A new query or filter: the old related clips belong to another search.
    private func requestChanged() {
        meaning.invalidate()
        relatedResults = []
        invalidateRequests()
    }

    private func invalidateRequests() {
        searchFailure = nil
        isSearching = true
        searchGeneration += 1
        pageRequest = nil
        isLoadingMore = false
    }

    public func search() async {
        invalidateRequests()
        let generation = searchGeneration
        defer { if generation == searchGeneration { isSearching = false } }
        // iOS pushes the kind filter into SQL; macOS narrows on the client
        // because its filter also feeds de-duplication and selection. That is
        // the only difference between the two loads, and it is expressed here
        // rather than hidden behind a flag.
        let page = await core.firstPage(
            query: query, boardID: selectedBoardID,
            sourceAppBundleID: selectedSourceAppBundleID,
            kinds: activeKinds)
        guard generation == searchGeneration, !Task.isCancelled else { return }
        if let failure = page.searchFailure {
            searchFailure = failure
            captures = []
            reachedEnd = true
            rebuildSections()
            return
        }
        captures = page.items
        reachedEnd = page.reachedEnd
        rebuildSections()
        startMeaning(generation: generation)
    }

    private func startMeaning(generation: Int) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let requested = ClipSearchQuery(
            text: query, kinds: activeKinds,
            sourceAppBundleID: selectedSourceAppBundleID, boardID: selectedBoardID)
        meaning.start(query: requested, source: meaningSource) { [weak self] items in
            guard let self, generation == searchGeneration else { return [] }
            relatedResults =
                HybridSearchResult(
                    conventional: captures, related: items, semanticState: .ready
                ).related
            return relatedResults
        }
    }

    /// Append the next page as the list nears its end (infinite scroll). No-ops
    /// unless the grouped recent view has more to load.
    public func loadMoreIfNeeded(_ item: ClipItem) async {
        guard isPaginatedView, !isLoadingMore, !reachedEnd,
            loadMoreTriggerIDs.contains(item.id)
        else { return }
        let request = UUID()
        let generation = searchGeneration
        pageRequest = request
        isLoadingMore = true
        defer {
            if pageRequest == request {
                pageRequest = nil
                isLoadingMore = false
            }
        }
        let board = selectedBoardID
        let offset = captures.count
        let page = await core.nextPage(after: offset, boardID: board)
        // The view may have changed during the await (query typed, board picked
        // or switched); only append if still extending the same list. The guard
        // stays here rather than in the core because it reads state only this
        // model has.
        guard generation == searchGeneration, pageRequest == request, !Task.isCancelled,
            isPaginatedView, selectedBoardID == board, captures.count == offset
        else { return }
        captures.append(contentsOf: page.items)
        if page.reachedEnd { reachedEnd = true }
        rebuildSections()
    }

    /// A header's count, only when the loaded rows can vouch for it: the last
    /// loaded group may still grow with the next page.
    public func headerCount(for group: ClipSectionGroup) -> HeaderCount? {
        let complete = reachedEnd && !reachedSearchCeiling
        guard complete || group.section != sections.last?.section else { return nil }
        return HeaderCount(value: group.clips.count, isAtLeast: false)
    }

    /// The flat list's count. A ranked search stops at its ceiling, so a full
    /// one reads as "at least"; a list still paging shows none.
    public var listCount: HeaderCount? {
        guard reachedEnd else { return nil }
        return HeaderCount(value: visibleClips.count, isAtLeast: reachedSearchCeiling)
    }

    /// A text, type or app search returns at most a ceiling of rows and then
    /// reports its end, though more may match.
    private var reachedSearchCeiling: Bool {
        let ceiling: Int
        if !query.isEmpty {
            ceiling = ClipListConfiguration.iOSHistory.searchLimitWithQuery
        } else if activeKinds != nil || selectedSourceAppBundleID != nil {
            ceiling = ClipListCore.searchLimitWithoutQuery
        } else {
            return false
        }
        return captures.count >= ceiling
    }

    /// Rebuild the cached date sections — after a load, or when the kind filter
    /// changes (so the Calendar math never lands on the scroll path).
    public func rebuildSections() {
        rebuildVisible()
        sections = isGroupedView ? ClipSections.grouped(visibleClips, now: Date()) : []
    }
}

/// What a section header can claim about how many rows it holds.
public struct HeaderCount: Equatable, Sendable {
    public let value: Int
    /// The list stopped at a ceiling, so there may be more.
    public let isAtLeast: Bool

    public init(value: Int, isAtLeast: Bool) {
        self.value = value
        self.isAtLeast = isAtLeast
    }
}

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
        visibleClips = kindFilter.map { kind in captures.filter { $0.kind == kind } } ?? captures
        loadMoreTriggerIDs = Set(visibleClips.suffix(Self.loadMoreThreshold).map(\.id))
    }

    /// Refreshes the app menu independently from text search so type-to-search
    /// does not repeat the aggregate metadata query on every keystroke.
    public func refreshSourceApps() async {
        sourceApps = await core.sourceApps(limit: 8)
    }

    public func search() async {
        // iOS pushes the kind filter into SQL; macOS narrows on the client
        // because its filter also feeds de-duplication and selection. That is
        // the only difference between the two loads, and it is expressed here
        // rather than hidden behind a flag.
        let page = await core.firstPage(
            query: query, boardID: selectedBoardID,
            sourceAppBundleID: selectedSourceAppBundleID,
            kinds: kindFilter.map { [$0] })
        captures = page.items
        reachedEnd = page.reachedEnd
        rebuildSections()
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
        let page = await core.nextPage(after: offset, boardID: board)
        // The view may have changed during the await (query typed, board picked
        // or switched); only append if still extending the same list. The guard
        // stays here rather than in the core because it reads state only this
        // model has.
        guard isPaginatedView, selectedBoardID == board, captures.count == offset else { return }
        captures.append(contentsOf: page.items)
        if page.reachedEnd { reachedEnd = true }
        rebuildSections()
    }

    /// Rebuild the cached date sections — after a load, or when the kind filter
    /// changes (so the Calendar math never lands on the scroll path).
    public func rebuildSections() {
        rebuildVisible()
        sections = isGroupedView ? ClipSections.grouped(visibleClips, now: Date()) : []
    }
}

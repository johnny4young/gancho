import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

/// A scriptable `PanelSearchSource` so the search/pagination/grouping rules can
/// run without a real store. It slices `recent` into pages exactly like the
/// GRDB `recentForBrowse`, so pagination boundaries (reachedEnd, mid-scroll
/// guard) are exercised honestly.
@MainActor private final class FakeSource: PanelSearchSource, MeaningSearchSource {
    var related: [ClipItem] = []
    var lastRelatedQuery: ClipSearchQuery?
    func relatedItems(for query: ClipSearchQuery) async throws -> MeaningSearchResponse {
        lastRelatedQuery = query
        return MeaningSearchResponse(
            items: related, coverage: SemanticIndexCoverage(eligible: 3, indexed: 3))
    }
    var isDurable = true
    var recent: [ClipItem] = []
    var searchResults: [ClipItem] = []
    var board: [ClipItem] = []
    var snippets: [String: ClipItem] = [:]
    var pending: Set<UUID> = []
    var sourceApps: [ClipSourceApp] = []
    var lastSearchQuery: ClipSearchQuery?
    var onSearch: (() -> Void)?
    var beforeSearch: (() async -> Void)?
    /// Runs inside `boardItems` — lets a test mutate the model "during" the
    /// await, to exercise the stale-page guard.
    var onBoardItems: (() -> Void)?

    func recentBrowse(offset: Int, limit: Int) async -> [ClipItem] {
        Array(recent.dropFirst(offset).prefix(limit))
    }
    func items(offset: Int, limit: Int) async -> [ClipItem] {
        Array(recent.dropFirst(offset).prefix(limit))
    }
    func boardItems(_ boardID: UUID, offset: Int, limit: Int) async -> [ClipItem] {
        onBoardItems?()
        return Array(board.dropFirst(offset).prefix(limit))
    }
    func search(_ query: ClipSearchQuery, limit: Int) async -> [ClipItem] {
        lastSearchQuery = query
        await beforeSearch?()
        onSearch?()
        return Array(searchResults.prefix(limit))
    }
    func recentSourceApps(limit: Int) async -> [ClipSourceApp] {
        Array(sourceApps.prefix(limit))
    }
    func snippet(matchingKeyword keyword: String) async -> ClipItem? { snippets[keyword] }
    /// How many times the model asked. The visible list is read once per row
    /// by the macOS row builder, so a per-read filter shows up here as a
    /// multiple of the row count.
    private(set) var deletionPendingCalls = 0
    func resetDeletionPendingCalls() { deletionPendingCalls = 0 }
    func isDeletionPending(_ id: UUID) -> Bool {
        deletionPendingCalls += 1
        return pending.contains(id)
    }
}

@MainActor
@Suite("Panel search model")
struct PanelSearchModelTests {
    private func items(_ n: Int, kind: ClipContentKind = .text) -> [ClipItem] {
        (0..<n).map { ClipItem(kind: kind, preview: "item \($0)") }
    }

    @Test func visibleIndicesFollowFilteringReorderingAndDeletionWithoutRepeatedScans() {
        let source = FakeSource()
        let model = PanelSearchModel(source: source)
        let text = ClipItem(kind: .text, preview: "text")
        let first = ClipItem(kind: .image, preview: "first")
        let second = ClipItem(kind: .image, preview: "second")
        model.results = [text, first, second, first]
        #expect(model.visibleIndex(of: second.id) == 2)
        model.kindFilter = .images
        #expect(model.visibleIndex(of: text.id) == nil)
        #expect(model.visibleIndex(of: first.id) == 0)
        #expect(model.visibleIndex(of: second.id) == 1)
        model.results = [second, first]
        #expect(model.visibleIndex(of: first.id) == 1)
        source.pending.insert(second.id)
        model.reconcileVisible()
        #expect(model.visibleIndex(of: second.id) == nil)
        #expect(model.visibleIndex(of: first.id) == 0)
        source.resetDeletionPendingCalls()
        for _ in 0..<1_000 { #expect(model.visibleIndex(of: first.id) == 0) }
        #expect(source.deletionPendingCalls == 0)
    }

    @Test func relatedArrivalPreservesConventionalOrderAndSelectedUUID() async {
        let source = FakeSource()
        source.searchResults = items(2)
        let related = ClipItem(preview: "Related synthetic clip")
        source.related = [source.searchResults[0], related]
        let model = PanelSearchModel(source: source)
        model.query = "synthetic"
        model.meaningEnabled = true
        await model.refresh()
        let literalIDs = model.results.map(\.id)
        let selectedID = model.selectedItem?.id
        for _ in 0..<10_000 {
            if model.meaning.status == .ready { break }
            await Task.yield()
        }
        #expect(model.meaning.status == .ready)
        #expect(Array(model.results.prefix(literalIDs.count)).map(\.id) == literalIDs)
        #expect(model.meaning.relatedIDs == [related.id])
        #expect(model.selectedItem?.id == selectedID)
        #expect(model.results.count == literalIDs.count + 1)
    }

    @Test func relatedArrivalDoesNotInventASelectionWhenLiteralResultsAreEmpty() async {
        let source = FakeSource()
        let item = ClipItem(preview: "Synthetic related result")
        source.related = [item]
        let model = PanelSearchModel(source: source)
        model.query = "unmatched"
        model.meaningEnabled = true
        await model.refresh()
        #expect(model.selectedItem == nil)
        for _ in 0..<10_000 {
            if model.meaning.status == .ready { break }
            await Task.yield()
        }
        #expect(model.meaning.status == .ready)
        #expect(model.selectedItem == nil)
        #expect(model.selectionCount == 0)
        model.moveSelection(by: 1, extending: false)
        #expect(model.selectedItem?.id == item.id)
        #expect(model.selectionCount == 1)
    }

    // MARK: - Recent load + pagination

    @Test func emptyQueryLoadsTheFirstRecentPageAndFlagsAShortList() async {
        let source = FakeSource()
        source.recent = items(30)
        let model = PanelSearchModel(source: source)
        await model.refresh()
        #expect(model.results.count == 30)
        #expect(model.reachedEnd)  // 30 < pageSize (100) → nothing more to load
        #expect(model.selectedIndex == 0)
    }

    @Test func loadMoreAppendsTheNextPageUntilExhausted() async {
        let source = FakeSource()
        source.recent = items(150)
        let model = PanelSearchModel(source: source)
        await model.refresh()
        #expect(model.results.count == 100)
        #expect(!model.reachedEnd)

        await model.loadMore()
        #expect(model.results.count == 150)
        #expect(model.reachedEnd)  // last page (50) < pageSize → done

        await model.loadMore()
        #expect(model.results.count == 150)  // no-op once exhausted
    }

    @Test func loadMoreDoesNothingWhileSearching() async {
        let source = FakeSource()
        source.recent = items(150)
        source.searchResults = items(10)
        let model = PanelSearchModel(source: source)
        model.query = "term"
        await model.refresh()
        #expect(model.results.count == 10)
        #expect(!model.isGroupedView)

        await model.loadMore()  // a ranked search is not a scroll-through
        #expect(model.results.count == 10)
    }

    // MARK: - Filtering, de-dupe, deletion hiding

    @Test func filteredDropsDuplicateIdsSoSelectionNeverSplits() async {
        let dup = ClipItem(preview: "dup")
        let source = FakeSource()
        source.recent = [dup, dup, ClipItem(preview: "other")]
        let model = PanelSearchModel(source: source)
        await model.refresh()
        #expect(model.results.count == 3)  // the raw load can carry the overlap
        #expect(model.filtered.count == 2)  // …but the list never repeats an id
    }

    @Test func filteredHidesClipsWhoseDeleteIsPending() async {
        let doomed = ClipItem(preview: "bye")
        let source = FakeSource()
        source.recent = [doomed, ClipItem(preview: "stay")]
        source.pending = [doomed.id]
        let model = PanelSearchModel(source: source)
        await model.refresh()
        #expect(model.filtered.count == 1)
        #expect(!model.filtered.contains { $0.id == doomed.id })
    }

    @Test func aDeleteAfterTheListIsBuiltHidesTheRowOnReconcile() async {
        // The real sequence, and the one the existing coverage missed: the list
        // exists first, and the delete happens against it. `pending` is state
        // this model does not own, so nothing tells a cached list it went
        // stale — the shell says so, synchronously, before its refresh.
        let doomed = ClipItem(preview: "bye")
        let source = FakeSource()
        source.recent = [doomed, ClipItem(preview: "stay")]
        let model = PanelSearchModel(source: source)
        await model.refresh()
        #expect(model.filtered.count == 2)

        source.pending = [doomed.id]
        model.reconcileVisible()

        #expect(model.filtered.count == 1)
        #expect(!model.filtered.contains { $0.id == doomed.id })
        // The recent list IS the grouped view, so this is the surface the user
        // actually looks at. Asserting `filtered` alone let a reconcile that
        // left the sections stale pass as a fix.
        #expect(model.isGroupedView)
        #expect(!model.groups.flatMap(\.rows).contains { $0.id == doomed.id })
        // The sections cover exactly `filtered`; a stale section would not.
        #expect(model.groups.flatMap(\.rows).map(\.id) == model.filtered.map(\.id))
    }

    @Test func anUndoneDeleteBringsTheRowBack() async {
        let restored = ClipItem(preview: "back")
        let source = FakeSource()
        source.recent = [restored, ClipItem(preview: "stay")]
        source.pending = [restored.id]
        let model = PanelSearchModel(source: source)
        await model.refresh()
        #expect(model.filtered.count == 1)
        #expect(!model.groups.flatMap(\.rows).contains { $0.id == restored.id })

        source.pending = []
        model.reconcileVisible()

        #expect(model.filtered.map(\.id).contains(restored.id))
        #expect(model.groups.flatMap(\.rows).contains { $0.id == restored.id })
        #expect(model.groups.flatMap(\.rows).map(\.id) == model.filtered.map(\.id))
    }

    @Test func theVisibleListIsBuiltOncePerChangeNotOncePerRead() async {
        let source = FakeSource()
        source.recent = (0..<50).map { ClipItem(preview: "clip \($0)") }
        let model = PanelSearchModel(source: source)
        await model.refresh()
        source.resetDeletionPendingCalls()

        // Reads the visible list the way a render does: the selection
        // accessors, the pagination guard, and once per row.
        for index in 0..<model.filtered.count {
            _ = model.filtered[index]
            _ = model.selectedItems
            _ = model.selectionCount
        }

        #expect(
            source.deletionPendingCalls == 0,
            "reading the list must not re-ask; it cost \(source.deletionPendingCalls) calls")

        model.reconcileVisible()
        #expect(source.deletionPendingCalls == 50, "one pass per rebuild, not per read")
    }

    @Test func kindFilterNarrowsToTheMatchingKind() async {
        let source = FakeSource()
        source.recent = [
            ClipItem(kind: .url, preview: "https://x"),
            ClipItem(kind: .text, preview: "plain"),
            ClipItem(kind: .url, preview: "https://y")
        ]
        let model = PanelSearchModel(source: source)
        await model.refresh()
        model.kindFilter = .links
        #expect(model.filtered.count == 2)
        #expect(model.filtered.allSatisfy { $0.kind == .url })
    }

    @Test func selectionKeepsVisibleOrderAcrossRangeAndCommandToggle() async {
        let source = FakeSource()
        source.recent = items(5)
        let model = PanelSearchModel(source: source)
        await model.refresh()

        model.moveSelection(by: 2, extending: true)
        model.select(4, toggling: true)

        #expect(model.selectionCount == 4)
        #expect(
            model.selectedItems.map(\.id) == [
                source.recent[0].id, source.recent[1].id, source.recent[2].id,
                source.recent[4].id
            ])
        #expect(model.selectedItem?.id == source.recent[4].id)
    }

    @Test func selectionSnapshotRemainsAvailableToPublicConsumers() async {
        let source = FakeSource()
        source.recent = items(4)
        let model = PanelSearchModel(source: source)
        await model.refresh()

        model.moveSelection(by: 2, extending: true)

        #expect(model.selection.cursorIndex == 2)
        #expect(model.selection.anchorID == source.recent[0].id)
        #expect(
            model.selection.selectedIDs == [
                source.recent[0].id, source.recent[1].id, source.recent[2].id
            ])
    }

    @Test func rebuildingAfterAFilterDropsHiddenSelections() async {
        let source = FakeSource()
        source.recent = [
            ClipItem(kind: .text, preview: "one"),
            ClipItem(kind: .url, preview: "https://example.com"),
            ClipItem(kind: .text, preview: "two")
        ]
        let model = PanelSearchModel(source: source)
        await model.refresh()
        model.moveSelection(by: 2, extending: true)

        model.kindFilter = .links
        model.rebuildGroups()

        #expect(model.selectionCount == 1)
        #expect(model.selectedItem?.id == source.recent[1].id)
        #expect(model.selectedItems.map(\.id) == [source.recent[1].id])
    }

    @Test func clearSelectionKeepsOnlyTheCursorRow() async {
        let source = FakeSource()
        source.recent = items(4)
        let model = PanelSearchModel(source: source)
        await model.refresh()
        model.moveSelection(by: 2, extending: true)

        model.clearSelection()

        #expect(model.selectionCount == 1)
        #expect(model.selectedIndex == 2)
        #expect(model.selectedItems.map(\.id) == [source.recent[2].id])
    }

    @Test func sourceAppFilterComposesWithBoardAndEmptyText() async {
        let source = FakeSource()
        let boardID = UUID()
        source.searchResults = [
            ClipItem(
                kind: .url, preview: "Safari", sourceAppBundleID: "com.apple.Safari")
        ]
        let model = PanelSearchModel(source: source)
        model.selectedBoardID = boardID
        model.selectedSourceAppBundleID = "com.apple.Safari"

        await model.refresh()

        #expect(model.results.count == 1)
        #expect(source.lastSearchQuery?.text.isEmpty == true)
        #expect(source.lastSearchQuery?.boardID == boardID)
        #expect(source.lastSearchQuery?.sourceAppBundleID == "com.apple.Safari")
        #expect(model.hasActiveFilter)
        #expect(!model.isGroupedView)
    }

    @Test func sourceAppOptionsAreLoadedAsContentFreeMetadata() async {
        let source = FakeSource()
        source.sourceApps = [ClipSourceApp(bundleID: "com.apple.Safari", clipCount: 7)]
        let model = PanelSearchModel(source: source)

        await model.refreshSourceApps()

        #expect(model.sourceApps == source.sourceApps)
    }

    // MARK: - Search vs recent modes

    @Test func aQueryTakesTheRankedSearchPathAndIsNotGrouped() async {
        let source = FakeSource()
        source.searchResults = items(5)
        let model = PanelSearchModel(source: source)
        model.query = "hello"
        await model.refresh()
        #expect(model.results.count == 5)
        #expect(model.reachedEnd)  // ranked top results, not a scroll-through
        #expect(!model.isGroupedView)
        #expect(model.groups.isEmpty)  // grouping only applies to the recent list
    }

    @Test func aSmallBoardLoadsInOnePageAndFlagsTheEnd() async {
        let source = FakeSource()
        source.board = items(4)
        let model = PanelSearchModel(source: source)
        model.selectedBoardID = UUID()
        await model.refresh()
        #expect(model.results.count == 4)
        #expect(model.reachedEnd)
        #expect(!model.isGroupedView)
    }

    @Test func aLargeBoardPagesLikeTheRecentList() async {
        let source = FakeSource()
        source.board = items(150)
        let model = PanelSearchModel(source: source)
        model.selectedBoardID = UUID()
        await model.refresh()
        #expect(model.results.count == 100)  // first page only, never the whole set
        #expect(!model.reachedEnd)

        await model.loadMore()
        #expect(model.results.count == 150)
        #expect(model.reachedEnd)  // last page (50) < pageSize → done

        await model.loadMore()
        #expect(model.results.count == 150)  // no-op once exhausted
    }

    @Test func aBoardPageArrivingAfterABoardSwitchIsDropped() async {
        let source = FakeSource()
        source.board = items(150)
        let model = PanelSearchModel(source: source)
        model.selectedBoardID = UUID()
        await model.refresh()
        #expect(model.results.count == 100)

        // The user switches boards while the next page is in flight — the
        // stale page must not append to the new board's list.
        source.onBoardItems = { model.selectedBoardID = UUID() }
        await model.loadMore()
        #expect(model.results.count == 100)
    }

    @Test func snippetMatchIsSetOnlyForANonEmptyKeywordHit() async {
        let snippet = ClipItem(title: "sig", preview: "signature")
        let source = FakeSource()
        source.snippets = ["sig": snippet]
        let model = PanelSearchModel(source: source)
        model.query = "sig"
        await model.refresh()
        #expect(model.snippetMatch?.id == snippet.id)

        model.query = ""
        await model.refresh()
        #expect(model.snippetMatch == nil)  // an empty query never offers an insert
    }

    // MARK: - Grouping

    @Test func rebuildGroupsPutsPinnedRowsInTheirOwnLeadingSection() async {
        let source = FakeSource()
        source.recent = [
            ClipItem(kind: .text, preview: "pinned", isPinned: true),
            ClipItem(kind: .text, preview: "recent 1"),
            ClipItem(kind: .text, preview: "recent 2")
        ]
        let model = PanelSearchModel(source: source)
        await model.refresh()
        #expect(model.isGroupedView)
        #expect(model.groups.first?.section == .pinned)
        #expect(model.groups.first?.rows.count == 1)
        // Sections concatenate to `filtered`, so the cursor math lines up.
        #expect(model.groups.flatMap(\.rows).map(\.id) == model.filtered.map(\.id))
        #expect(model.filtered.map { model.visibleIndex(of: $0.id) } == [0, 1, 2])
    }

    // MARK: - In-memory fallback

    @Test func withoutADurableStoreEmptyQueryStillPaginatesViaTheProtocolOrdering() async {
        let source = FakeSource()
        source.isDurable = false
        source.recent = items(30)
        let model = PanelSearchModel(source: source)
        await model.refresh()
        #expect(model.results.count == 30)
        #expect(model.reachedEnd)
    }

    @Test func withoutADurableStoreAQueryFiltersClientSide() async {
        let source = FakeSource()
        source.isDurable = false
        source.recent = [
            ClipItem(preview: "alpha"), ClipItem(preview: "beta"), ClipItem(preview: "ALPHAbet")
        ]
        let model = PanelSearchModel(source: source)
        model.query = "alpha"
        await model.refresh()
        #expect(model.results.count == 2)  // case-insensitive contains over the preview
    }

    @Test("Without a durable store a type filter narrows the in-memory list instead of emptying it")
    func withoutADurableStoreAKindFilterFiltersClientSide() async {
        let source = FakeSource()
        source.isDurable = false
        source.recent = [
            ClipItem(kind: .url, preview: "https://example.test/one"),
            ClipItem(preview: "plain text"),
            ClipItem(kind: .url, preview: "https://example.test/two")
        ]
        let model = PanelSearchModel(source: source)
        model.kindFilter = .links
        await model.refresh()
        #expect(model.results.count == 2)
        #expect(source.lastSearchQuery == nil, "the durable-only search API is never asked")
        model.query = "two"
        await model.refresh()
        #expect(model.results.map(\.preview) == ["https://example.test/two"])
    }

    @Test("Without a durable store pinned-only and exact mode also apply locally")
    func withoutADurableStorePinnedAndModeFilterClientSide() async {
        let source = FakeSource()
        source.isDurable = false
        source.recent = [
            ClipItem(preview: "alpha beta", isPinned: true), ClipItem(preview: "alpha"),
            ClipItem(preview: "beta alpha", isPinned: true)
        ]
        let model = PanelSearchModel(source: source)
        model.pinnedOnly = true
        await model.refresh()
        #expect(model.results.count == 2)
        model.mode = .exact
        model.query = "alpha beta"
        await model.refresh()
        #expect(model.results.map(\.preview) == ["alpha beta"])
    }
}

extension PanelSearchModelTests {
    @Test(arguments: [false, true])
    func cancelledMeaningIntentDuringConventionalReadDoesNotStartLater(navigate: Bool) async {
        let source = FakeSource()
        let literal = ClipItem(preview: "Synthetic literal")
        source.searchResults = [literal]
        source.related = [ClipItem(preview: "Synthetic related")]
        let model = PanelSearchModel(source: source)
        model.query = "synthetic"
        model.results = [literal]
        model.meaningEnabled = true
        source.onSearch = {
            if navigate { model.select(0) } else { model.cancelMeaningSearch() }
        }
        await model.refresh()
        #expect(model.results.map(\.id) == [literal.id])
        #expect(model.meaning.status == .idle)
        await Task.yield()
        #expect(source.lastRelatedQuery == nil)
    }

    @Test func sameQueryRefreshRestoresSelectedRelatedUUIDAfterRankingChanges() async {
        let source = FakeSource()
        let first = ClipItem(preview: "First synthetic related")
        let second = ClipItem(preview: "Second synthetic related")
        source.related = [first, second]
        let model = PanelSearchModel(source: source)
        model.query = "unmatched"
        model.meaningEnabled = true
        await model.refresh()
        for _ in 0..<10_000 {
            if model.meaning.status == .ready { break }
            await Task.yield()
        }
        #expect(model.meaning.status == .ready)
        model.select(0)
        #expect(model.selectedItem?.id == first.id)
        source.related = [second, first]
        source.onSearch = {
            #expect(model.meaning.relatedIDs == [first.id, second.id])
        }
        await model.refresh()
        for _ in 0..<10_000 {
            if model.meaning.status == .ready { break }
            await Task.yield()
        }
        #expect(model.meaning.status == .ready)
        #expect(model.selectedItem?.id == first.id)
        #expect(model.selectedIndex == 1)
    }

}

extension PanelSearchModelTests {
    @Test func immediatePasteResolvesTheNewQueryInsteadOfThePreviousSelection() async {
        let source = FakeSource()
        source.recent = [ClipItem(preview: "Previous synthetic clip")]
        let current = ClipItem(preview: "Current synthetic result")
        source.searchResults = [current]
        let model = PanelSearchModel(source: source)
        await model.refresh()
        model.query = "current"
        #expect(!model.hasCurrentResults)
        let target = await model.resolvePasteTarget(includingSnippet: true)
        #expect(target?.item.id == current.id)
        #expect(target?.isSnippet == false)
    }

    @Test func immediatePasteDoesNotFallBackToOldRowsForAnEmptyResult() async {
        let source = FakeSource()
        source.recent = [ClipItem(preview: "Previous synthetic clip")]
        let model = PanelSearchModel(source: source)
        await model.refresh()
        model.query = "no match"
        let target = await model.resolvePasteTarget(includingSnippet: true)
        #expect(target == nil)
    }

    @Test(arguments: [false, true])
    func immediatePastePreservesSnippetVersusPlainSelectionSemantics(includeSnippet: Bool) async {
        let source = FakeSource()
        let result = ClipItem(preview: "Search result")
        let snippet = ClipItem(preview: "Snippet body")
        source.searchResults = [result]
        source.snippets["sig"] = snippet
        let model = PanelSearchModel(source: source)
        model.query = "sig"
        let target = await model.resolvePasteTarget(includingSnippet: includeSnippet)
        #expect(target?.item.id == (includeSnippet ? snippet.id : result.id))
        #expect(target?.isSnippet == includeSnippet)
    }

    @Test(arguments: [false, true])
    func queryChangeOrDismissalCancelsAPasteWaitingForResults(changeQuery: Bool) async {
        let source = FakeSource()
        source.searchResults = [ClipItem(preview: "Synthetic result")]
        let model = PanelSearchModel(source: source)
        model.query = "first"
        source.onSearch = {
            if changeQuery { model.query = "second" } else { model.cancelPendingPaste() }
        }
        let target = await model.resolvePasteTarget(includingSnippet: true)
        #expect(target == nil)
    }

    @Test func currentSelectionDoesNotRefreshOrJumpBeforePasting() async {
        let source = FakeSource()
        source.searchResults = items(3)
        let model = PanelSearchModel(source: source)
        model.query = "item"
        await model.refresh()
        model.select(2)
        source.onSearch = { Issue.record("A current selection must not be searched again") }
        let target = await model.resolvePasteTarget(includingSnippet: false)
        #expect(target?.item.id == source.searchResults[2].id)
    }
}

extension PanelSearchModelTests {
    @Test func clearingTheQueryBeforePasteReturnsToRecents() async {
        let source = FakeSource()
        let recent = ClipItem(preview: "Recent synthetic clip")
        source.recent = [recent]
        source.searchResults = [ClipItem(preview: "Old search result")]
        let model = PanelSearchModel(source: source)
        model.query = "old"
        await model.refresh()
        model.query = ""
        let target = await model.resolvePasteTarget(includingSnippet: true)
        #expect(target?.item.id == recent.id)
    }

    @Test func newerPasteRequestSupersedesAnInFlightRequest() async {
        let source = FakeSource()
        let result = ClipItem(preview: "Synthetic result")
        source.searchResults = [result]
        let model = PanelSearchModel(source: source)
        model.query = "result"
        var releaseFirst: CheckedContinuation<Void, Never>?
        var reads = 0
        source.beforeSearch = {
            reads += 1
            if reads == 1 {
                await withCheckedContinuation { releaseFirst = $0 }
            }
        }
        let firstInteraction = model.pasteInteractionID
        let first = Task { await model.resolvePasteTarget(includingSnippet: true) }
        while releaseFirst == nil { await Task.yield() }
        // A new query and Enter must not wait for the obsolete storage read.
        model.query = "newer result"
        #expect(model.pasteInteractionID != firstInteraction)
        let secondInteraction = model.pasteInteractionID
        let second = await model.resolvePasteTarget(includingSnippet: true)
        #expect(model.pasteInteractionID == secondInteraction)
        releaseFirst?.resume()
        let superseded = await first.value
        #expect(model.pasteInteractionID == secondInteraction)
        #expect(superseded == nil)
        #expect(second?.item.id == result.id)
    }
}

extension PanelSearchModelTests {
    @Test func newInputBeforeThePasteTaskStartsCancelsTheCapturedKeyAction() async {
        let source = FakeSource()
        source.searchResults = [ClipItem(preview: "Synthetic result")]
        let model = PanelSearchModel(source: source)
        model.query = "first"
        let request = model.beginPasteRequest()
        model.query = "second"
        let target = await model.resolvePasteTarget(includingSnippet: true, requestID: request)
        #expect(target == nil)
    }

    @Test func enteringThePeekCancelsAPasteWaitingForResults() async {
        let source = FakeSource()
        source.searchResults = [ClipItem(preview: "Synthetic result")]
        let model = PanelSearchModel(source: source)
        model.query = "result"
        source.onSearch = { model.endNewestFollow() }
        let target = await model.resolvePasteTarget(includingSnippet: true)
        #expect(target == nil)
    }
}

extension PanelSearchModelTests {
    @Test func pasteRequestKeysCoalesceOnlyIdenticalEffectiveIntents() {
        let interaction = UUID()
        let enter = PanelSearchModel.PasteRequestKey(
            interaction: interaction, plain: false, includingSnippet: true)
        #expect(
            enter == PanelSearchModel.PasteRequestKey(
                interaction: interaction, plain: false, includingSnippet: true))
        #expect(
            enter != PanelSearchModel.PasteRequestKey(
                interaction: interaction, plain: true, includingSnippet: true))
        #expect(
            enter != PanelSearchModel.PasteRequestKey(
                interaction: interaction, plain: false, includingSnippet: false))
        #expect(
            enter != PanelSearchModel.PasteRequestKey(
                interaction: UUID(), plain: false, includingSnippet: true))
    }

    @Test(arguments: [false, true])
    func changedPasteModeSupersedesPendingEnterWithoutChangingTheQuery(plain: Bool) async {
        let source = FakeSource()
        let result = ClipItem(preview: "Synthetic selected result")
        let snippet = ClipItem(preview: "Synthetic snippet")
        source.searchResults = [result]
        source.snippets["sig"] = snippet
        let model = PanelSearchModel(source: source)
        model.query = "sig"
        var releaseFirst: CheckedContinuation<Void, Never>?
        var reads = 0
        source.beforeSearch = {
            reads += 1
            if reads == 1 {
                await withCheckedContinuation { releaseFirst = $0 }
            }
        }
        let interaction = model.pasteInteractionID
        let firstRequest = model.beginPasteRequest()
        let first = Task {
            await model.resolvePasteTarget(includingSnippet: true, requestID: firstRequest)
        }
        while releaseFirst == nil { await Task.yield() }
        // Option-Return keeps snippet priority; Command-V selects the row.
        let replacementKey = PanelSearchModel.PasteRequestKey(
            interaction: interaction, plain: plain, includingSnippet: plain)
        let secondRequest = model.beginPasteRequest()
        let second = await model.resolvePasteTarget(
            includingSnippet: replacementKey.includingSnippet, requestID: secondRequest)
        #expect(model.pasteInteractionID == interaction)
        releaseFirst?.resume()
        let superseded = await first.value
        #expect(superseded == nil)
        #expect(second?.item.id == (plain ? snippet.id : result.id))
        #expect(second?.isSnippet == plain)
    }

    @Test(arguments: [false, true])
    func enteringTheFilterRailCancelsPendingPasteWithoutChangingSelection(navigate: Bool) async {
        let source = FakeSource()
        source.searchResults = [ClipItem(preview: "Synthetic result")]
        let model = PanelSearchModel(source: source)
        model.query = "result"
        source.onSearch = {
            guard navigate else { return }
            let state = PanelNavigationState(selectedIndex: 0)
            let result = PanelNavigation.reduce(
                .up, state: state,
                context: PanelNavigationContext(rowCount: 1, boardIDs: [], hasSelection: true))
            #expect(result.state.railFocus == .filters(0))
            #expect(result.state.selectedIndex == state.selectedIndex)
            if result.state.railFocus != state.railFocus { model.cancelPendingPaste() }
        }
        let target = await model.resolvePasteTarget(includingSnippet: false)
        #expect((target == nil) == navigate)
    }
}

extension PanelSearchModelTests {
    @Test(arguments: [false, true])
    func openingShortcutsCancelsPendingPasteButClosingDoesNot(opening: Bool) async {
        let source = FakeSource()
        source.searchResults = [ClipItem(preview: "Synthetic result")]
        let model = PanelSearchModel(source: source)
        model.query = "result"
        source.onSearch = {
            if opening { model.cancelPendingPaste() }
        }
        let target = await model.resolvePasteTarget(includingSnippet: false)
        #expect((target == nil) == opening)
    }
}

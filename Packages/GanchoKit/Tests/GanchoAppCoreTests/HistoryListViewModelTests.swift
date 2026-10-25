import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

/// A scriptable `HistoryListSource` for the iOS list model — slices `recent`
/// into pages like GRDB's `recentForBrowse` so pagination boundaries are
/// exercised honestly.
@MainActor private final class FakeSource: HistoryListSource {
    var isDurable = true
    var recent: [ClipItem] = []
    var searchResults: [ClipItem] = []
    var board: [ClipItem] = []
    var sourceApps: [ClipSourceApp] = []
    var lastSearchQuery: ClipSearchQuery?
    /// When set, the next recent-page read snapshots `recent`, then waits on
    /// the gate before answering — a query that ran early and answers late.
    var holdNextRecentBrowse: SearchGate?

    func recentBrowse(offset: Int, limit: Int) async -> [ClipItem] {
        let snapshot = recent
        if let gate = holdNextRecentBrowse {
            holdNextRecentBrowse = nil
            await gate.hold()
        }
        return Array(snapshot.dropFirst(offset).prefix(limit))
    }
    func items(offset: Int, limit: Int) async -> [ClipItem] {
        Array(recent.dropFirst(offset).prefix(limit))
    }
    // Board queries and ranked search need a durable store — the real
    // `HistoryStoreSource` returns [] otherwise, so the fake mirrors that.
    func boardItems(_ boardID: UUID, offset: Int, limit: Int) async -> [ClipItem] {
        isDurable ? Array(board.dropFirst(offset).prefix(limit)) : []
    }
    func search(_ query: ClipSearchQuery, limit: Int) async -> [ClipItem] {
        lastSearchQuery = query
        return isDurable ? Array(searchResults.prefix(limit)) : []
    }
    func recentSourceApps(limit: Int) async -> [ClipSourceApp] {
        Array(sourceApps.prefix(limit))
    }
}

/// Answers related-by-meaning with a fixed set, fully indexed.
@MainActor private final class FakeMeaning: MeaningSearchSource {
    var items: [ClipItem] = []
    var lastQuery: ClipSearchQuery?
    func relatedItems(for query: ClipSearchQuery) async throws -> MeaningSearchResponse {
        lastQuery = query
        return MeaningSearchResponse(
            items: items,
            coverage: SemanticIndexCoverage(eligible: items.count, indexed: items.count))
    }
}

/// Parks one read until the test releases it, and reports when it is parked.
actor SearchGate {
    private var waiter: CheckedContinuation<Void, Never>?
    private var entered = false

    func hold() async {
        entered = true
        await withCheckedContinuation { waiter = $0 }
    }

    func waitUntilEntered() async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while !entered, ContinuousClock.now < deadline { await Task.yield() }
        return entered
    }

    func release() {
        waiter?.resume()
        waiter = nil
    }
}

@MainActor
@Suite("History list view model (iOS)", .timeLimit(.minutes(1)))
struct HistoryListViewModelTests {
    private func items(_ n: Int, kind: ClipContentKind = .text) -> [ClipItem] {
        (0..<n).map { ClipItem(kind: kind, preview: "item \($0)") }
    }

    @Test(
        "A page from before a same-sized refresh cannot append stale rows or clear a newer spinner")
    func refreshInvalidatesOldPageOwnership() async {
        let source = FakeSource()
        source.recent = items(150)
        let model = HistoryListViewModel(source: source)
        await model.search()
        let oldGate = SearchGate()
        source.holdNextRecentBrowse = oldGate
        let oldPage = Task { await model.loadMoreIfNeeded(model.captures[85]) }
        #expect(await oldGate.waitUntilEntered())

        source.recent = items(150)
        let freshIDs = source.recent.map(\.id)
        await model.search()
        let newGate = SearchGate()
        source.holdNextRecentBrowse = newGate
        let newPage = Task { await model.loadMoreIfNeeded(model.captures[85]) }
        let entered = await newGate.waitUntilEntered()
        #expect(entered, "a stale request must not block pagination of the refreshed list")
        await oldGate.release()
        await oldPage.value
        #expect(model.captures.map(\.id) == Array(freshIDs.prefix(100)))
        if entered { #expect(model.isLoadingMore) }
        await newGate.release()
        await newPage.value
        #expect(model.captures.map(\.id) == freshIDs)
        #expect(!model.isLoadingMore)
    }

    @Test("Headers count only what the loaded rows can vouch for")
    func headerCounts() async {
        let source = FakeSource()
        let now = Date()
        let pinned = ClipItem(createdAt: now, preview: "pinned", contentHash: "p", isPinned: true)
        let today = (0..<3).map {
            ClipItem(createdAt: now, preview: "t\($0)", contentHash: "t\($0)")
        }
        let old = (0..<(ClipListCore.pageSize + 5)).map {
            ClipItem(
                createdAt: now.addingTimeInterval(-400 * 86_400), preview: "o\($0)",
                contentHash: "o\($0)")
        }
        source.recent = [pinned] + today + old
        let model = HistoryListViewModel(source: source)
        await model.search()
        let counts = model.sections.map { model.headerCount(for: $0)?.value }
        #expect(counts.first == 1, "Pinned is complete")
        #expect(counts.dropFirst().first == 3, "Today is complete")
        #expect(counts.last == .some(nil), "the last loaded group may still grow")
        #expect(model.listCount == nil)

        await model.loadMoreIfNeeded(model.captures[model.captures.count - 1])
        #expect(
            model.headerCount(for: model.sections[model.sections.count - 1])?.value == old.count)
    }

    @Test("A search at its ceiling counts as at least that many")
    func searchCount() async {
        let source = FakeSource()
        let ceiling = ClipListConfiguration.iOSHistory.searchLimitWithQuery
        source.searchResults = items(ceiling + 10)
        let model = HistoryListViewModel(source: source)
        model.query = "item"
        await model.search()
        #expect(model.listCount == HeaderCount(value: ceiling, isAtLeast: true))
        source.searchResults = items(3)
        await model.search()
        #expect(model.listCount == HeaderCount(value: 3, isAtLeast: false))

        // An app filter with no text is a search too, with its own ceiling.
        model.query = ""
        model.selectedSourceAppBundleID = "com.apple.mobilesafari"
        source.searchResults = items(ClipListCore.searchLimitWithoutQuery + 1)
        await model.search()
        #expect(
            model.listCount
                == HeaderCount(value: ClipListCore.searchLimitWithoutQuery, isAtLeast: true))
    }

    @Test("A typed search lists related clips after the results, without repeating one")
    func relatedByMeaning() async {
        let source = FakeSource()
        let hits = items(2)
        source.searchResults = hits
        let meaning = FakeMeaning()
        let extra = ClipItem(preview: "related", contentHash: "related")
        meaning.items = [hits[0], extra]
        let model = HistoryListViewModel(source: source)
        model.meaningSource = meaning
        model.kindFilter = .text
        model.query = "item"
        await model.search()
        let deadline = ContinuousClock.now + .seconds(5)
        while model.meaning.status == .loading, ContinuousClock.now < deadline {
            await Task.yield()
        }
        #expect(model.related.map(\.id) == [extra.id], "a result never repeats as related")
        #expect(meaning.lastQuery?.kinds == [.text], "the filters scope related clips too")

        await model.search()
        #expect(
            model.related.map(\.id) == [extra.id],
            "a refresh of the same search keeps its related clips while it re-runs")

        model.query = "other"
        #expect(model.related.isEmpty, "a new query drops the old related clips at once")
        model.query = ""
        await model.search()
        #expect(model.meaning.status == .idle, "no query, no meaning search")
    }

    @Test("Changing filters invalidates a suspended search before the next search starts")
    func filterChangeRejectsSuspendedSearch() async {
        let source = FakeSource()
        source.recent = items(30)
        let model = HistoryListViewModel(source: source)
        let gate = SearchGate()
        source.holdNextRecentBrowse = gate
        let pending = Task { await model.search() }
        #expect(await gate.waitUntilEntered())
        model.kindFilter = .image
        await gate.release()
        await pending.value
        #expect(model.captures.isEmpty)
    }

    @Test("Cancelled pagination does not append rows")
    func cancelledPageIsRejected() async {
        let source = FakeSource()
        source.recent = items(150)
        let model = HistoryListViewModel(source: source)
        await model.search()
        let gate = SearchGate()
        source.holdNextRecentBrowse = gate
        let pending = Task { await model.loadMoreIfNeeded(model.captures[85]) }
        #expect(await gate.waitUntilEntered())
        pending.cancel()
        await gate.release()
        await pending.value
        #expect(model.captures.count == 100)
        #expect(!model.isLoadingMore)
    }

    /// A paste starts two searches: the hint refresh before the insert and
    /// the reload after it. The one that queried first may answer last; its
    /// pre-insert page must not replace the newer list.
    @Test func anEarlierSearchThatAnswersLateNeverReplacesTheNewerList() async {
        let source = FakeSource()
        let model = HistoryListViewModel(source: source)
        let gate = SearchGate()
        source.holdNextRecentBrowse = gate
        let early = Task { await model.search() }
        #expect(await gate.waitUntilEntered(), "the early search never reached its read")
        source.recent = items(1)
        await model.search()
        #expect(model.captures.count == 1)
        await gate.release()
        await early.value
        #expect(model.captures.count == 1, "the stale pre-insert page replaced the list")
    }

    @Test func emptyQueryLoadsTheFirstRecentPageAndFlagsAShortList() async {
        let source = FakeSource()
        source.recent = items(30)
        let model = HistoryListViewModel(source: source)
        await model.search()
        #expect(model.captures.count == 30)
        #expect(model.isGroupedView)
        #expect(model.sections.first?.section == .date(.today))  // all created "now"
    }

    @Test func pagesAppendViaLoadMoreUntilExhausted() async {
        let source = FakeSource()
        source.recent = items(150)
        let model = HistoryListViewModel(source: source)
        await model.search()
        #expect(model.captures.count == 100)

        // The trigger clip must be within 20 of the end for the prefetch to fire.
        await model.loadMoreIfNeeded(model.captures[85])
        #expect(model.captures.count == 150)

        await model.loadMoreIfNeeded(model.captures[140])
        #expect(model.captures.count == 150)  // exhausted → no-op
    }

    @Test func theLoadMoreThresholdIsExactlyTwentyRowsFromTheEnd() async {
        // The guard used to be `index >= count - 20`, found with a linear
        // search per appearing row; it is a set of the trailing ids now. Same
        // boundary, so pin it: with 100 loaded, row 80 pulls and row 79 does
        // not.
        let source = FakeSource()
        source.recent = items(150)
        let model = HistoryListViewModel(source: source)
        await model.search()
        #expect(model.captures.count == 100)

        await model.loadMoreIfNeeded(model.captures[79])
        #expect(model.captures.count == 100, "one row short of the threshold must not pull")

        await model.loadMoreIfNeeded(model.captures[80])
        #expect(model.captures.count == 150, "the threshold row itself must pull")
    }

    @Test func loadMoreIsANoOpFarFromTheEnd() async {
        let source = FakeSource()
        source.recent = items(150)
        let model = HistoryListViewModel(source: source)
        await model.search()
        await model.loadMoreIfNeeded(model.captures[0])  // top of the list
        #expect(model.captures.count == 100)
    }

    @Test func kindFilterNarrowsVisibleClipsWithoutDisturbingCaptures() async {
        let source = FakeSource()
        source.recent = [
            ClipItem(kind: .url, preview: "https://x"),
            ClipItem(kind: .text, preview: "plain"),
            ClipItem(kind: .url, preview: "https://y")
        ]
        let model = HistoryListViewModel(source: source)
        await model.search()
        model.kindFilter = .url
        #expect(model.captures.count == 3)  // the loaded page is untouched
        #expect(model.visibleClips.count == 2)  // the filter applies on top
    }

    @Test func sourceAppFilterComposesWithKindBoardAndEmptyText() async {
        let source = FakeSource()
        let boardID = UUID()
        source.searchResults = [
            ClipItem(
                kind: .url, preview: "Safari", sourceAppBundleID: "com.apple.Safari")
        ]
        let model = HistoryListViewModel(source: source)
        model.kindFilter = .url
        model.selectedBoardID = boardID
        model.selectedSourceAppBundleID = "com.apple.Safari"

        await model.search()

        #expect(model.captures.count == 1)
        #expect(source.lastSearchQuery?.text.isEmpty == true)
        #expect(source.lastSearchQuery?.kinds == [.url])
        #expect(source.lastSearchQuery?.boardID == boardID)
        #expect(source.lastSearchQuery?.sourceAppBundleID == "com.apple.Safari")
        #expect(!model.isGroupedView)
    }

    @Test func sourceAppOptionsAreLoadedAsContentFreeMetadata() async {
        let source = FakeSource()
        source.sourceApps = [ClipSourceApp(bundleID: "com.apple.mobilesafari", clipCount: 4)]
        let model = HistoryListViewModel(source: source)

        await model.refreshSourceApps()

        #expect(model.sourceApps == source.sourceApps)
    }

    @Test func filteredInfiniteScrollUsesTheVisibleTail() async {
        let source = FakeSource()
        source.recent =
            [ClipItem(kind: .url, preview: "https://first")]
            + items(99, kind: .text)
            + items(50, kind: .url)
        let model = HistoryListViewModel(source: source)
        await model.search()
        model.kindFilter = .url
        #expect(model.captures.count == 100)
        #expect(model.visibleClips.count == 1)

        await model.loadMoreIfNeeded(model.visibleClips[0])

        #expect(model.captures.count == 150)
        #expect(model.visibleClips.count == 51)
    }

    /// A sparse kind used to filter only the loaded recent page, so a first
    /// page with none of that kind showed an empty list with nothing to scroll.
    @Test func aKindFilterWithoutTextLoadsMatchesBeyondTheFirstRecentPage() async {
        let source = FakeSource()
        source.recent = items(150, kind: .text)
        source.searchResults = items(3, kind: .image)
        let model = HistoryListViewModel(source: source)
        model.kindFilter = .image

        await model.search()

        #expect(model.visibleClips.count == 3)
        #expect(source.lastSearchQuery?.text.isEmpty == true)
        #expect(source.lastSearchQuery?.kinds == [.image])
        #expect(model.isGroupedView, "an empty query still groups by date")
        #expect(model.sections.flatMap(\.clips).count == 3)

        await model.loadMoreIfNeeded(model.visibleClips[2])
        #expect(model.captures.count == 3, "a filter-only search is bounded, never paged")
    }

    @Test func aQueryTakesTheRankedSearchPathAndIsNotGrouped() async {
        let source = FakeSource()
        source.searchResults = items(5)
        let model = HistoryListViewModel(source: source)
        model.query = "hello"
        await model.search()
        #expect(model.captures.count == 5)
        #expect(!model.isGroupedView)
        #expect(model.sections.isEmpty)  // grouping only applies to the recent list
    }

    @Test func aSmallBoardLoadsInOnePage() async {
        let source = FakeSource()
        source.board = items(4)
        let model = HistoryListViewModel(source: source)
        model.selectedBoardID = UUID()
        await model.search()
        #expect(model.captures.count == 4)
        #expect(!model.isGroupedView)
    }

    @Test func aLargeBoardPagesViaLoadMoreLikeTheRecentList() async {
        let source = FakeSource()
        source.board = items(150)
        let model = HistoryListViewModel(source: source)
        model.selectedBoardID = UUID()
        await model.search()
        #expect(model.captures.count == 100)  // first page only, never the whole set

        await model.loadMoreIfNeeded(model.captures[85])
        #expect(model.captures.count == 150)

        await model.loadMoreIfNeeded(model.captures[140])
        #expect(model.captures.count == 150)  // exhausted → no-op
    }

    @Test func rebuildSectionsPutsPinnedRowsInTheirOwnLeadingSection() async {
        let source = FakeSource()
        source.recent = [
            ClipItem(kind: .text, preview: "pinned", isPinned: true),
            ClipItem(kind: .text, preview: "recent 1")
        ]
        let model = HistoryListViewModel(source: source)
        await model.search()
        #expect(model.sections.first?.section == .pinned)
        #expect(model.sections.first?.clips.count == 1)
    }

    @Test func withoutADurableStoreQueryReturnsNothingAndRecentStillPaginates() async {
        let source = FakeSource()
        source.isDurable = false
        source.recent = items(30)
        source.searchResults = items(9)
        let model = HistoryListViewModel(source: source)

        await model.search()  // empty query → recent page via the fallback
        #expect(model.captures.count == 30)

        model.query = "term"
        await model.search()  // no durable store → ranked search is unavailable
        #expect(model.captures.isEmpty)
    }
}

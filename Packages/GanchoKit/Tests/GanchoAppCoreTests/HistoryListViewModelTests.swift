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

    func recentBrowse(offset: Int, limit: Int) async -> [ClipItem] {
        Array(recent.dropFirst(offset).prefix(limit))
    }
    func items(offset: Int, limit: Int) async -> [ClipItem] {
        Array(recent.dropFirst(offset).prefix(limit))
    }
    // Board queries and ranked search need a durable store — the real
    // `HistoryStoreSource` returns [] otherwise, so the fake mirrors that.
    func boardItems(_ boardID: UUID) async -> [ClipItem] { isDurable ? board : [] }
    func search(_ query: ClipSearchQuery, limit: Int) async -> [ClipItem] {
        isDurable ? searchResults : []
    }
}

@MainActor
@Suite("History list view model (iOS)")
struct HistoryListViewModelTests {
    private func items(_ n: Int, kind: ClipContentKind = .text) -> [ClipItem] {
        (0..<n).map { ClipItem(kind: kind, preview: "item \($0)") }
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

    @Test func aSelectedBoardLoadsTheCuratedSetWhole() async {
        let source = FakeSource()
        source.board = items(4)
        let model = HistoryListViewModel(source: source)
        model.selectedBoardID = UUID()
        await model.search()
        #expect(model.captures.count == 4)
        #expect(!model.isGroupedView)
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

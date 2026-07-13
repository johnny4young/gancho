import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

/// A scriptable `PanelSearchSource` so the search/pagination/grouping rules can
/// run without a real store. It slices `recent` into pages exactly like the
/// GRDB `recentForBrowse`, so pagination boundaries (reachedEnd, mid-scroll
/// guard) are exercised honestly.
@MainActor private final class FakeSource: PanelSearchSource {
    var isDurable = true
    var recent: [ClipItem] = []
    var searchResults: [ClipItem] = []
    var board: [ClipItem] = []
    var snippets: [String: ClipItem] = [:]
    var pending: Set<UUID> = []
    var sourceApps: [ClipSourceApp] = []
    var lastSearchQuery: ClipSearchQuery?

    func recentBrowse(offset: Int, limit: Int) async -> [ClipItem] {
        Array(recent.dropFirst(offset).prefix(limit))
    }
    func items(offset: Int, limit: Int) async -> [ClipItem] {
        Array(recent.dropFirst(offset).prefix(limit))
    }
    func boardItems(_ boardID: UUID) async -> [ClipItem] { board }
    func search(_ query: ClipSearchQuery, limit: Int) async -> [ClipItem] {
        lastSearchQuery = query
        return Array(searchResults.prefix(limit))
    }
    func recentSourceApps(limit: Int) async -> [ClipSourceApp] {
        Array(sourceApps.prefix(limit))
    }
    func snippet(matchingKeyword keyword: String) async -> ClipItem? { snippets[keyword] }
    func isDeletionPending(_ id: UUID) -> Bool { pending.contains(id) }
}

@MainActor
@Suite("Panel search model")
struct PanelSearchModelTests {
    private func items(_ n: Int, kind: ClipContentKind = .text) -> [ClipItem] {
        (0..<n).map { ClipItem(kind: kind, preview: "item \($0)") }
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

    @Test func aSelectedBoardLoadsTheCuratedSetWhole() async {
        let source = FakeSource()
        source.board = items(4)
        let model = PanelSearchModel(source: source)
        model.selectedBoardID = UUID()
        await model.refresh()
        #expect(model.results.count == 4)
        #expect(model.reachedEnd)
        #expect(!model.isGroupedView)
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
        // The row indices are global across sections, so the cursor math lines up.
        #expect(model.groups.flatMap { $0.rows.map(\.index) } == [0, 1, 2])
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
}

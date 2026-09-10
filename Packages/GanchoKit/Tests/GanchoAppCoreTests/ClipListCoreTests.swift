import ClipboardCore
import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

/// Records what the list actually asked the store for, so a test can assert on
/// the REQUEST and not only on what came back. The divergences between the two
/// shells live in the request — a search ceiling, a pushed-down kind filter —
/// and none of them are visible in the returned rows.
@MainActor private final class RecordingSource: ClipListSource {
    var isDurable = true
    var recent: [ClipItem] = []
    var board: [ClipItem] = []
    var hits: [ClipItem] = []
    var protocolItems: [ClipItem] = []

    private(set) var searchQueries: [(query: ClipSearchQuery, limit: Int)] = []
    private(set) var recentBrowseCalls: [(offset: Int, limit: Int)] = []
    private(set) var itemsCalls: [(offset: Int, limit: Int)] = []
    private(set) var boardCalls: [(id: UUID, offset: Int, limit: Int)] = []

    func recentBrowse(offset: Int, limit: Int) async -> [ClipItem] {
        recentBrowseCalls.append((offset, limit))
        return Array(recent.dropFirst(offset).prefix(limit))
    }

    func items(offset: Int, limit: Int) async -> [ClipItem] {
        itemsCalls.append((offset, limit))
        return Array(protocolItems.dropFirst(offset).prefix(limit))
    }

    func boardItems(_ boardID: UUID, offset: Int, limit: Int) async -> [ClipItem] {
        boardCalls.append((boardID, offset, limit))
        return Array(board.dropFirst(offset).prefix(limit))
    }

    func search(_ query: ClipSearchQuery, limit: Int) async -> [ClipItem] {
        searchQueries.append((query, limit))
        return hits
    }

    func recentSourceApps(limit: Int) async -> [ClipSourceApp] { [] }
}

@Suite("ClipListCore — one load path, two configured shells")
@MainActor
struct ClipListCoreTests {
    private func clip(_ preview: String, uses: Int = 0, lastUsedAt: Date? = nil) -> ClipItem {
        ClipItem(
            lastUsedAt: lastUsedAt, kind: .text, preview: preview, contentHash: preview,
            uses: uses)
    }

    // MARK: - The shape rules both shells derive from the same three fields

    @Test("Grouping is the recent list only; a board or a filter flattens it")
    func groupingShape() {
        #expect(ClipListShape.isGrouped(query: "", boardID: nil, sourceAppBundleID: nil))
        #expect(!ClipListShape.isGrouped(query: "x", boardID: nil, sourceAppBundleID: nil))
        #expect(!ClipListShape.isGrouped(query: "", boardID: UUID(), sourceAppBundleID: nil))
        #expect(!ClipListShape.isGrouped(query: "", boardID: nil, sourceAppBundleID: "com.a"))
    }

    @Test("A board paginates; a query or app filter is a bounded top-N")
    func paginationShape() {
        // A board is grouped=false but paginated=true — the one combination
        // that is easy to get wrong, and the reason these are separate rules.
        #expect(ClipListShape.isPaginated(query: "", sourceAppBundleID: nil))
        #expect(!ClipListShape.isPaginated(query: "x", sourceAppBundleID: nil))
        #expect(!ClipListShape.isPaginated(query: "", sourceAppBundleID: "com.a"))
        #expect(!ClipListShape.isGrouped(query: "", boardID: UUID(), sourceAppBundleID: nil))
    }

    // MARK: - Parity: the same fake, both configurations

    @Test("The recent list loads identically on both shells")
    func recentPageIsIdenticalAcrossShells() async {
        let rows = (0..<(ClipListCore.pageSize + 20)).map { clip("c\($0)") }
        var pages: [ClipListPage] = []
        var browseLimits: [Int] = []
        for configuration in [ClipListConfiguration.macOSPanel, .iOSHistory] {
            let source = RecordingSource()
            source.recent = rows
            let core = ClipListCore(source: source, configuration: configuration)
            pages.append(
                await core.firstPage(query: "", boardID: nil, sourceAppBundleID: nil))
            browseLimits.append(source.recentBrowseCalls.map(\.limit).first ?? -1)
        }
        #expect(pages[0] == pages[1], "the recent list is not shell-specific")
        #expect(pages[0].items.count == ClipListCore.pageSize)
        #expect(!pages[0].reachedEnd, "a full page means the store may have more")
        #expect(browseLimits == [ClipListCore.pageSize, ClipListCore.pageSize])
    }

    @Test("A short page is the end, on both shells")
    func shortPageEndsPagination() async {
        for configuration in [ClipListConfiguration.macOSPanel, .iOSHistory] {
            let source = RecordingSource()
            source.recent = (0..<7).map { clip("c\($0)") }
            let page = await ClipListCore(source: source, configuration: configuration)
                .firstPage(query: "", boardID: nil, sourceAppBundleID: nil)
            #expect(page.items.count == 7)
            #expect(page.reachedEnd)
        }
    }

    // MARK: - The divergences, asserted as the ONLY divergences

    @Test("The search ceiling is the configured one, and differs by shell")
    func searchCeilingFollowsConfiguration() async {
        // This is a real, pre-existing difference — macOS shows 100 ranked hits,
        // iOS 50 — that used to be a literal buried in each model.
        var limits: [Int] = []
        for configuration in [ClipListConfiguration.macOSPanel, .iOSHistory] {
            let source = RecordingSource()
            let core = ClipListCore(source: source, configuration: configuration)
            _ = await core.firstPage(query: "term", boardID: nil, sourceAppBundleID: nil)
            limits.append(source.searchQueries.first?.limit ?? -1)
        }
        // Derived, so tuning a ceiling moves the test with it — and asserted
        // as a DIFFERENCE too, because deriving alone would still pass if both
        // shells were set to the same number, which is the drift worth catching.
        #expect(
            limits == [
                ClipListConfiguration.macOSPanel.searchLimitWithQuery,
                ClipListConfiguration.iOSHistory.searchLimitWithQuery
            ])
        #expect(limits[0] != limits[1], "the two shells stopped diverging here")
    }

    @Test("A filter with no text raises the ceiling on both shells")
    func emptyQueryUsesTheBrowsingCeiling() async {
        var limits: [Int] = []
        for configuration in [ClipListConfiguration.macOSPanel, .iOSHistory] {
            let source = RecordingSource()
            let core = ClipListCore(source: source, configuration: configuration)
            _ = await core.firstPage(query: "", boardID: nil, sourceAppBundleID: "com.a")
            limits.append(source.searchQueries.first?.limit ?? -1)
        }
        #expect(
            limits == [ClipListCore.searchLimitWithoutQuery, ClipListCore.searchLimitWithoutQuery],
            "browsing a filter is not homing in on a phrase")
    }

    @Test("Frecency re-ranks search on macOS and leaves iOS in store order")
    func frecencyAppliesOnlyWhereConfigured() async {
        let now = Date()
        // Last in FTS order, but heavily used yesterday.
        let habitual = clip("habitual", uses: 40, lastUsedAt: now.addingTimeInterval(-86_400))
        let hits = [clip("first"), clip("second"), habitual]

        let mac = RecordingSource()
        mac.hits = hits
        let macPage = await ClipListCore(source: mac, configuration: .macOSPanel)
            .firstPage(query: "term", boardID: nil, sourceAppBundleID: nil)

        let ios = RecordingSource()
        ios.hits = hits
        let iosPage = await ClipListCore(source: ios, configuration: .iOSHistory)
            .firstPage(query: "term", boardID: nil, sourceAppBundleID: nil)

        #expect(macPage.items.first?.preview == "habitual")
        #expect(iosPage.items.map(\.preview) == ["first", "second", "habitual"])
    }

    @Test("The kind filter reaches SQL only when the caller pushes it")
    func kindFilterReachesTheQueryOnlyWhenPassed() async {
        // macOS narrows on the client and passes nil; iOS pushes it down. The
        // difference is in the CALL, not in a flag, so this is what pins it.
        let pushed = RecordingSource()
        _ = await ClipListCore(source: pushed, configuration: .iOSHistory)
            .firstPage(
                query: "term", boardID: nil, sourceAppBundleID: nil, kinds: [.image])
        #expect(pushed.searchQueries.first?.query.kinds == [.image])

        let clientSide = RecordingSource()
        _ = await ClipListCore(source: clientSide, configuration: .macOSPanel)
            .firstPage(query: "term", boardID: nil, sourceAppBundleID: nil)
        #expect(clientSide.searchQueries.first?.query.kinds == nil)
    }

    // MARK: - The non-durable fallback

    @Test("Without a durable store both shells scan a bounded slice and filter it")
    func clientSideFallbackIsBoundedAndFiltered() async {
        for configuration in [ClipListConfiguration.macOSPanel, .iOSHistory] {
            let source = RecordingSource()
            source.isDurable = false
            source.protocolItems = [clip("alpha"), clip("beta"), clip("alphabet")]
            let core = ClipListCore(source: source, configuration: configuration)
            let page = await core.firstPage(
                query: "alpha", boardID: nil, sourceAppBundleID: nil)

            #expect(page.items.map(\.preview).sorted() == ["alpha", "alphabet"])
            #expect(page.reachedEnd, "the fallback is one bounded scan, never paged")
            #expect(
                source.itemsCalls.first?.limit == ClipListCore.clientFallbackLimit,
                "the scan must stay bounded")
            #expect(source.searchQueries.isEmpty, "no FTS without a durable store")
        }
    }

    @Test("Without a durable store a board falls back to the recent list")
    func boardWithoutDurableStoreDoesNotQueryTheBoard() async {
        let source = RecordingSource()
        source.isDurable = false
        source.protocolItems = [clip("a"), clip("b")]
        let page = await ClipListCore(source: source, configuration: .macOSPanel)
            .firstPage(query: "", boardID: UUID(), sourceAppBundleID: nil)

        #expect(source.boardCalls.isEmpty, "there are no board queries to make")
        #expect(page.items.map(\.preview) == ["a", "b"])
    }

    // MARK: - Paging

    @Test("The next page continues the board or the recent list from the offset")
    func nextPageContinuesTheSameList() async {
        let boardID = UUID()
        let source = RecordingSource()
        let overflow = ClipListCore.pageSize + ClipListCore.pageSize / 2
        source.recent = (0..<overflow).map { clip("r\($0)") }
        source.board = (0..<overflow).map { clip("b\($0)") }
        let core = ClipListCore(source: source, configuration: .macOSPanel)

        let recentNext = await core.nextPage(after: ClipListCore.pageSize, boardID: nil)
        #expect(recentNext.items.first?.preview == "r\(ClipListCore.pageSize)")
        #expect(recentNext.reachedEnd, "a half page is a short page")
        #expect(source.recentBrowseCalls.last?.offset == ClipListCore.pageSize)

        let boardNext = await core.nextPage(after: ClipListCore.pageSize, boardID: boardID)
        #expect(boardNext.items.first?.preview == "b\(ClipListCore.pageSize)")
        #expect(source.boardCalls.last?.offset == ClipListCore.pageSize)
    }
}

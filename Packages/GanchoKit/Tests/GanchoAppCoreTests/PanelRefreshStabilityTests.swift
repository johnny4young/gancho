import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

@MainActor private final class SuspendedPanelSource: PanelSearchSource {
    var isDurable = true
    var recent: [ClipItem] = []
    var snippet: ClipItem?
    var suspendPages = true
    var suspendFirstPage = false
    private var pages: [CheckedContinuation<Void, Never>?] = []
    private var pageWaiters: [(Int, CheckedContinuation<Void, Never>)] = []
    private var firstPage: CheckedContinuation<Void, Never>?
    private var firstWaiter: CheckedContinuation<Void, Never>?

    func recentBrowse(offset: Int, limit: Int) async -> [ClipItem] {
        let page = Array(recent.dropFirst(offset).prefix(limit))
        if offset > 0, suspendPages {
            await withCheckedContinuation { continuation in
                pages.append(continuation)
                let ready = pageWaiters.filter { $0.0 <= pages.count }
                pageWaiters.removeAll { $0.0 <= pages.count }
                for (_, waiter) in ready { waiter.resume() }
            }
        } else if offset == 0, suspendFirstPage {
            await withCheckedContinuation { continuation in
                firstPage = continuation
                firstWaiter?.resume()
                firstWaiter = nil
            }
        }
        return page
    }
    func waitForPage(_ count: Int = 1) async {
        if pages.count >= count { return }
        await withCheckedContinuation { pageWaiters.append((count, $0)) }
    }
    func releasePage(_ index: Int = 0) {
        pages[index]?.resume()
        pages[index] = nil
    }
    func waitForFirstPage() async {
        if firstPage != nil { return }
        await withCheckedContinuation { firstWaiter = $0 }
    }
    func releaseFirstPage() {
        firstPage?.resume()
        firstPage = nil
    }
    func items(offset: Int, limit: Int) async -> [ClipItem] {
        Array(recent.dropFirst(offset).prefix(limit))
    }
    func boardItems(_ boardID: UUID, offset: Int, limit: Int) async -> [ClipItem] { [] }
    func search(_ query: ClipSearchQuery, limit: Int) async -> [ClipItem] {
        Array(recent.prefix(limit))
    }
    func recentSourceApps(limit: Int) async -> [ClipSourceApp] { [] }
    func snippet(matchingKeyword keyword: String) async -> ClipItem? { snippet }
    func isDeletionPending(_ id: UUID) -> Bool { false }
}

@MainActor @Suite("Panel refresh identity and request ownership", .timeLimit(.minutes(1)))
struct PanelRefreshStabilityTests {
    @Test func unchangedQueryRefreshPreservesSelectedIdentity() async {
        let source = SuspendedPanelSource()
        source.recent = (0..<4).map { ClipItem(preview: "synthetic-\($0)") }
        let model = PanelSearchModel(source: source)
        await model.refresh()
        model.select(2)
        let selected = model.selectedItem?.id
        source.recent.insert(ClipItem(preview: "synthetic-incoming"), at: 0)
        await model.refresh()
        #expect(model.selectedItem?.id == selected)
    }

    @Test func oldPageCannotAppendAfterSameSizedRefresh() async {
        let source = SuspendedPanelSource()
        source.recent = (0..<150).map { ClipItem(preview: "synthetic-old-\($0)") }
        let model = PanelSearchModel(source: source)
        await model.refresh()
        let loading = Task { await model.loadMore() }
        await source.waitForPage()
        source.recent = (0..<100).map { ClipItem(preview: "synthetic-new-\($0)") }
        await model.refresh()
        let refreshed = model.results.map(\.id)
        source.releasePage()
        await loading.value
        #expect(model.results.map(\.id) == refreshed)
    }
    @Test func multiselectionAndCursorSurviveReordering() async {
        let source = SuspendedPanelSource()
        let rows = (0..<5).map { ClipItem(preview: "synthetic-\($0)") }
        source.recent = rows
        let model = PanelSearchModel(source: source)
        await model.refresh()
        model.select(1)
        model.select(3, toggling: true)
        source.recent = [rows[4], rows[3], rows[0], rows[1], rows[2]]
        await model.refresh()
        #expect(model.selectedItem?.id == rows[3].id)
        #expect(model.selection.selectedIDs == [rows[1].id, rows[3].id])
        #expect(model.selectedItems.map(\.id) == [rows[3].id, rows[1].id])
    }

    @Test func deletedCursorUsesNearestVisibleFallback() async {
        let source = SuspendedPanelSource()
        let rows = (0..<4).map { ClipItem(preview: "synthetic-\($0)") }
        source.recent = rows
        let model = PanelSearchModel(source: source)
        await model.refresh()
        model.select(2)
        source.recent.remove(at: 2)
        await model.refresh()
        #expect(model.selectedItem?.id == rows[3].id)
        source.recent = []
        await model.refresh()
        #expect(model.selectedItem == nil)
        #expect(model.selection.selectedIDs.isEmpty)
    }

    @Test func aNewQueryResetsButTheSameQueryPreservesSelection() async {
        let source = SuspendedPanelSource()
        source.recent = (0..<4).map { ClipItem(preview: "synthetic-\($0)") }
        let model = PanelSearchModel(source: source)
        await model.refresh()
        model.select(2)
        model.query = "synthetic"
        await model.refresh()
        #expect(model.selectedIndex == 0)
        model.select(2)
        let selected = model.selectedItem?.id
        await model.refresh()
        #expect(model.selectedItem?.id == selected)
    }

    @Test func staleCompletionCannotClearANewerPagesBusyState() async {
        let source = SuspendedPanelSource()
        source.recent = (0..<150).map { ClipItem(preview: "old-\($0)") }
        let model = PanelSearchModel(source: source)
        await model.refresh()
        let oldPage = Task { await model.loadMore() }
        await source.waitForPage()
        source.recent = (0..<200).map { ClipItem(preview: "new-\($0)") }
        await model.refresh()
        let newPage = Task { await model.loadMore() }
        await source.waitForPage(2)
        source.releasePage()
        await oldPage.value
        #expect(model.isLoadingMore)
        #expect(model.results.count == 100)
        #expect(!model.reachedEnd)
        source.releasePage(1)
        await newPage.value
        #expect(!model.isLoadingMore)
        #expect(model.results.count == 200)
    }

    @Test func cancelledPageDoesNotAppend() async {
        let source = SuspendedPanelSource()
        source.recent = (0..<150).map { ClipItem(preview: "synthetic-\($0)") }
        let model = PanelSearchModel(source: source)
        await model.refresh()
        let page = Task { await model.loadMore() }
        await source.waitForPage()
        page.cancel()
        source.releasePage()
        await page.value
        #expect(model.results.count == 100)
        #expect(!model.isLoadingMore)
        #expect(!model.reachedEnd)
    }

    @Test func changingContextAwayAndBackStillInvalidatesTheOldPage() async {
        let source = SuspendedPanelSource()
        source.recent = (0..<150).map { ClipItem(preview: "synthetic-\($0)") }
        let model = PanelSearchModel(source: source)
        await model.refresh()
        let page = Task { await model.loadMore() }
        await source.waitForPage()
        model.selectedBoardID = UUID()
        model.selectedBoardID = nil
        source.releasePage()
        await page.value
        #expect(model.results.count == 100)
        #expect(!model.isLoadingMore)
    }

    @Test func selectionMadeWhileRefreshingWinsOverAStartOfRequestSnapshot() async {
        let source = SuspendedPanelSource()
        let rows = (0..<5).map { ClipItem(preview: "synthetic-\($0)") }
        source.recent = rows
        let model = PanelSearchModel(source: source)
        await model.refresh()
        model.select(1)
        source.recent.insert(ClipItem(preview: "incoming"), at: 0)
        source.suspendFirstPage = true
        let refresh = Task { await model.refresh() }
        await source.waitForFirstPage()
        model.select(3)
        source.releaseFirstPage()
        await refresh.value
        #expect(model.selectedItem?.id == rows[3].id)
    }

    @Test func refreshKeepsTheLoadedWindowAndBoundarySelection() async {
        let source = SuspendedPanelSource()
        source.suspendPages = false
        source.recent = (0..<250).map { ClipItem(preview: "synthetic-\($0)") }
        let model = PanelSearchModel(source: source)
        await model.refresh()
        model.select(99)
        let boundary = model.selectedItem?.id
        source.recent.insert(ClipItem(preview: "incoming"), at: 0)
        await model.refresh()
        #expect(model.selectedItem?.id == boundary)
        #expect(model.selectedIndex == 100)
        model.select(150)
        let laterPage = model.selectedItem?.id
        await model.refresh()
        #expect(model.selectedItem?.id == laterPage)
        #expect(model.results.count >= 200)
    }

    @Test func changingQueryImmediatelyInvalidatesTheOldSnippetAction() async {
        let source = SuspendedPanelSource()
        source.snippet = ClipItem(preview: "synthetic snippet")
        let model = PanelSearchModel(source: source)
        model.query = "old"
        await model.refresh()
        #expect(model.snippetMatch != nil)
        model.query = "new"
        #expect(model.snippetMatch == nil)
    }

}

import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

@MainActor
private final class PasteFreshnessSource: PanelSearchSource {
    var isDurable = true
    let result = ClipItem(preview: "Synthetic conventional result")
    let snippet = ClipItem(preview: "Synthetic exact-keyword snippet")
    var additionalResults: [ClipItem] = []
    var recent: [ClipItem] = []

    func recentBrowse(offset: Int, limit: Int) async -> [ClipItem] {
        Array(recent.dropFirst(offset).prefix(limit))
    }
    func items(offset: Int, limit: Int) async -> [ClipItem] {
        Array(recent.dropFirst(offset).prefix(limit))
    }
    func boardItems(_ boardID: UUID, offset: Int, limit: Int) async -> [ClipItem] { [] }
    func search(_ query: ClipSearchQuery, limit: Int) async -> [ClipItem] {
        Array(([result] + additionalResults).prefix(limit))
    }
    func recentSourceApps(limit: Int) async -> [ClipSourceApp] { [] }
    func snippet(matchingKeyword keyword: String) async -> ClipItem? {
        keyword == "sig" ? snippet : nil
    }
    func isDeletionPending(_ id: UUID) -> Bool { false }
}

@MainActor
@Suite("Panel paste freshness regressions")
struct PanelPasteFreshnessRegressionTests {
    @Test(arguments: [false, true])
    func invalidatedSnippetLookupIsResolvedBeforeEnter(roundTripQuery: Bool) async {
        let source = PasteFreshnessSource()
        let model = PanelSearchModel(source: source)
        model.query = "sig"
        await model.refresh()
        #expect(model.snippetMatch?.id == source.snippet.id)

        if roundTripQuery {
            model.query = "other"
            model.query = "sig"
        } else {
            model.meaningEnabled = true
        }

        #expect(!model.hasCurrentResults)
        #expect(model.snippetMatch == nil)
        let target = await model.resolvePasteTarget(includingSnippet: true)
        #expect(target?.isSnippet == true)
        #expect(target?.item.id == source.snippet.id)
        #expect(model.hasCurrentResults)
        #expect(model.snippetMatch?.id == source.snippet.id)
    }

    @Test func meaningToggleRefreshPreservesTheConventionalCursor() async {
        let source = PasteFreshnessSource()
        let selected = ClipItem(preview: "Synthetic selected result")
        source.additionalResults = [selected]
        let model = PanelSearchModel(source: source)
        model.query = "sig"
        await model.refresh()
        model.select(1)

        model.meaningEnabled = true
        let target = await model.resolvePasteTarget(includingSnippet: true)

        #expect(target?.item.id == source.snippet.id)
        #expect(model.selectedItem?.id == selected.id)
        #expect(model.selectedIndex == 1)
    }

    @Test func meaningToggleRefreshPreservesTheLoadedBrowseWindow() async {
        let source = PasteFreshnessSource()
        source.recent = (0..<150).map { ClipItem(preview: "Synthetic recent \($0)") }
        let model = PanelSearchModel(source: source)
        await model.refresh()
        await model.loadMore()
        model.select(140)

        model.meaningEnabled = true
        let target = await model.resolvePasteTarget(includingSnippet: false)

        #expect(target?.item.id == source.recent[140].id)
        #expect(model.selectedIndex == 140)
        #expect(model.results.count == 150)
        #expect(model.hasCurrentResults)
    }
}

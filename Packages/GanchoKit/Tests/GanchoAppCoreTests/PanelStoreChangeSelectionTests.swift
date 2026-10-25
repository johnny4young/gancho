import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

@MainActor private final class SelectionSource: PanelSearchSource, MeaningSearchSource {
    var recent: [ClipItem] = []
    var related: [ClipItem] = []
    let isDurable = true

    func relatedItems(for query: ClipSearchQuery) async throws -> MeaningSearchResponse {
        MeaningSearchResponse(
            items: related, coverage: SemanticIndexCoverage(eligible: 2, indexed: 2))
    }
    func recentBrowse(offset: Int, limit: Int) async -> [ClipItem] {
        Array(recent.dropFirst(offset).prefix(limit))
    }
    func items(offset: Int, limit: Int) async -> [ClipItem] {
        Array(recent.dropFirst(offset).prefix(limit))
    }
    func boardItems(_ boardID: UUID, offset: Int, limit: Int) async -> [ClipItem] { [] }
    func search(_ query: ClipSearchQuery, limit: Int) async -> [ClipItem] { [] }
    func recentSourceApps(limit: Int) async -> [ClipSourceApp] { [] }
    func snippet(matchingKeyword keyword: String) async -> ClipItem? { nil }
    func isDeletionPending(_ id: UUID) -> Bool { false }
}

@MainActor @Suite("Panel store-change selection")
struct PanelStoreChangeSelectionTests {
    private func waitForMeaning(_ model: PanelSearchModel) async {
        for _ in 0..<10_000 {
            if model.meaning.status == .ready { break }
            await Task.yield()
        }
    }

    @Test("A store-change refresh restores a selected related row")
    func restoresSelectedRelatedRow() async {
        let source = SelectionSource()
        let first = ClipItem(preview: "First synthetic related")
        let second = ClipItem(preview: "Second synthetic related")
        source.related = [first, second]
        let model = PanelSearchModel(source: source)
        model.query = "unmatched"
        model.meaningEnabled = true
        await model.refresh()
        await waitForMeaning(model)
        model.select(0)
        #expect(model.selectedItem?.id == first.id)
        source.related = [second, first]
        await model.refreshAfterStoreChange(preview: PanelPreviewModel())
        await waitForMeaning(model)
        #expect(model.meaning.status == .ready)
        #expect(model.selectedItem?.id == first.id)
        #expect(model.selectedIndex == 1)
    }

    @Test("A store-change refresh keeps a surviving selection when another row goes")
    func keepsSurvivingSelection() async throws {
        let source = SelectionSource()
        source.recent = (0..<5).map { ClipItem(preview: "synthetic item \($0)") }
        let model = PanelSearchModel(source: source)
        await model.refresh()
        model.select(3)
        let selected = try #require(model.selectedItem)
        source.recent.remove(at: 1)
        await model.refreshAfterStoreChange(preview: PanelPreviewModel())
        #expect(model.filtered.count == 4)
        #expect(model.selectedItem?.id == selected.id)
        #expect(model.selectedIndex == 2)
    }
}

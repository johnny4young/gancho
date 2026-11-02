import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

@MainActor private final class ContextSource: PanelSearchSource {
    var isDurable = true
    var recent: [ClipItem] = []
    var pool: [ClipItem] = []
    private(set) var ranges: [ClosedRange<Date>] = []

    func recentBrowse(offset: Int, limit: Int) async -> [ClipItem] {
        Array(recent.dropFirst(offset).prefix(limit))
    }
    func items(offset: Int, limit: Int) async -> [ClipItem] { [] }
    func boardItems(_ boardID: UUID, offset: Int, limit: Int) async -> [ClipItem] { [] }
    func search(_ query: ClipSearchQuery, limit: Int) async -> [ClipItem] {
        recent.filter { $0.preview.contains(query.text) }
    }
    func searchOutcome(_ query: ClipSearchQuery, limit: Int) async -> ClipListSearchOutcome {
        .success(await search(query, limit: limit))
    }
    func recentSourceApps(limit: Int) async -> [ClipSourceApp] { [] }
    func snippet(matchingKeyword keyword: String) async -> ClipItem? { nil }
    func isDeletionPending(_ id: UUID) -> Bool { false }
    func clipsCreated(in range: ClosedRange<Date>) async -> [ClipItem] {
        ranges.append(range)
        return pool.filter { range.contains($0.createdAt) }.sorted { $0.createdAt < $1.createdAt }
    }
}

@MainActor
@Suite("Panel jump to context")
struct PanelContextModeTests {
    private let base = Date(timeIntervalSince1970: 1_800_000_000)

    private func clip(_ name: String, minutes: Double, kind: ClipContentKind = .text) -> ClipItem {
        ClipItem(createdAt: base.addingTimeInterval(minutes * 60), kind: kind, preview: name)
    }

    /// A search for "fix" selects the anchor; the pool holds its session.
    private func setUp() async -> (PanelSearchModel, ContextSource, ClipItem) {
        let source = ContextSource()
        let anchor = clip("fix focus", minutes: 0, kind: .code)
        let before = clip("panel docs", minutes: -1)
        let after = clip("issue link", minutes: 2, kind: .url)
        let outside = clip("lunch", minutes: 3)
        let other = clip("fix typo", minutes: -60)
        source.recent = [other, anchor]
        source.pool = [before, anchor, after, outside, other]
        let model = PanelSearchModel(source: source)
        model.query = "fix"
        await model.refresh()
        model.select(model.filtered.firstIndex { $0.id == anchor.id }!)
        return (model, source, anchor)
    }

    @Test("⌘J lists the session ±2 min around the anchor's first copy, anchor selected")
    func enter() async throws {
        let (model, source, anchor) = await setUp()
        await model.enterContext()
        #expect(model.isShowingContext)
        #expect(model.contextAnchorID == anchor.id)
        #expect(model.filtered.map(\.preview) == ["panel docs", "fix focus", "issue link"])
        #expect(model.selectedItem?.id == anchor.id)
        #expect(!model.isGroupedView)
        #expect(model.hasCurrentResults, "Return pastes from the context list")
        let window = PanelSearchModel.contextWindow
        #expect(
            source.ranges.last
                == anchor.createdAt.addingTimeInterval(
                    -window)...anchor.createdAt
                .addingTimeInterval(window))
    }

    @Test("esc restores the results and the row ⌘J was pressed on")
    func exit() async {
        let (model, _, anchor) = await setUp()
        let before = model.filtered.map(\.id)
        await model.enterContext()
        // Up to "panel docs": a cursor that merely clamped would land on "fix typo".
        model.moveSelection(by: -1, extending: false)
        model.exitContext()
        #expect(!model.isShowingContext)
        #expect(model.filtered.map(\.id) == before)
        #expect(model.selectedItem?.id == anchor.id)
        await model.refresh()
        #expect(model.query == "fix")
        #expect(model.selectedItem?.id == anchor.id, "the refresh after esc keeps the row")
    }

    @Test("A type filter doesn't hide the session, and typing leaves context mode")
    func filtersAndTyping() async {
        let (model, _, _) = await setUp()
        model.kindFilter = .code
        await model.refresh()
        model.select(0)
        await model.enterContext()
        #expect(model.filtered.count == 3, "the whole session, not only code")
        model.query = "lunch"
        #expect(!model.isShowingContext)
    }

    @Test("A store change re-reads the window and keeps the cursor")
    func storeChange() async {
        let (model, source, anchor) = await setUp()
        await model.enterContext()
        model.moveSelection(by: 1, extending: false)
        let selected = model.selectedItem?.id
        source.pool.append(clip("new note", minutes: 1))
        await model.refreshAfterStoreChange()
        #expect(model.isShowingContext)
        #expect(model.filtered.map(\.preview).contains("new note"))
        #expect(model.selectedItem?.id == selected)
        #expect(model.contextAnchorID == anchor.id)
    }

    @Test("From the date-grouped recent list, the session shows flat, without sections")
    func fromRecentList() async {
        let (model, _, anchor) = await setUp()
        model.query = ""
        await model.refresh()
        model.select(model.filtered.firstIndex { $0.id == anchor.id }!)
        #expect(model.isGroupedView)
        await model.enterContext()
        #expect(!model.isGroupedView)
        #expect(model.groups.isEmpty)
        model.exitContext()
        #expect(model.isGroupedView)
    }

    @Test("Without a durable store the anchor still shows, alone")
    func noStore() async {
        let (model, source, anchor) = await setUp()
        source.pool = []
        await model.enterContext()
        #expect(model.filtered.map(\.id) == [anchor.id])
    }
}

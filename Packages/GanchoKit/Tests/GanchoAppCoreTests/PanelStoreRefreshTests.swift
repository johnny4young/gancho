import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

@MainActor private final class StoreRefreshSource: PanelSearchSource {
    let store: GRDBClipboardStore
    let isDurable = true
    private(set) var failedReads = 0

    init(store: GRDBClipboardStore) { self.store = store }

    private func read(_ action: () async throws -> [ClipItem]) async -> [ClipItem] {
        do { return try await action() } catch {
            failedReads += 1
            return []
        }
    }

    func recentBrowse(offset: Int, limit: Int) async -> [ClipItem] {
        await read { try await store.recentForBrowse(offset: offset, limit: limit) }
    }
    func items(offset: Int, limit: Int) async -> [ClipItem] {
        await read { try await store.items(offset: offset, limit: limit) }
    }
    func boardItems(_ boardID: UUID, offset: Int, limit: Int) async -> [ClipItem] { [] }
    func search(_ query: ClipSearchQuery, limit: Int) async -> [ClipItem] {
        await read { try await store.search(query, limit: limit) }
    }
    func recentSourceApps(limit: Int) async -> [ClipSourceApp] { [] }
    func snippet(matchingKeyword keyword: String) async -> ClipItem? { nil }
    func isDeletionPending(_ id: UUID) -> Bool { false }
}

private struct PanelStoreFixture {
    let directory: URL
    let store: GRDBClipboardStore
    let victim: ClipItem
    let now = Date()
    static let body = "syntheticpanelrefresh full body differs from preview"

    init(insideRecentPage: Bool) async throws {
        let temporaryRoot = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        directory = temporaryRoot.appendingPathComponent(
            "gancho-panel-refresh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
        precondition(directory.deletingLastPathComponent() == temporaryRoot)
        store = try GRDBClipboardStore(directory: directory.appendingPathComponent("store"))
        victim = ClipItem(
            createdAt: now.addingTimeInterval(insideRecentPage ? -1 : -10_000),
            preview: "synthetic metadata", contentHash: "synthetic-victim",
            expiresAt: now.addingTimeInterval(3600))
        var entries: [(item: ClipItem, content: ClipContent?)] = (0..<50).map { index in
            let item = ClipItem(
                createdAt: now.addingTimeInterval(-100 - Double(index)),
                preview: "synthetic survivor \(index)", contentHash: "synthetic-survivor-\(index)")
            return (item, .text("synthetic survivor \(index)"))
        }
        entries.append((victim, .text(Self.body)))
        try await store.importBatch(entries)
    }
}

@MainActor @Suite("Panel store-mutation refresh", .serialized, .timeLimit(.minutes(1)))
struct PanelStoreRefreshTests {
    @Test("A purge inside the recent page clears filtered rows, selection and preview")
    func purgeInsideRecentPage() async throws {
        try await verifyPurge(insideRecentPage: true)
    }

    @Test("A purge outside the recent page clears the panel even when recents are equal")
    func purgeOutsideRecentPage() async throws {
        try await verifyPurge(insideRecentPage: false)
    }

    private func verifyPurge(insideRecentPage: Bool) async throws {
        let fixture = try await PanelStoreFixture(insideRecentPage: insideRecentPage)
        defer { try? FileManager.default.removeItem(at: fixture.directory) }
        let store = fixture.store
        let reuse = ReuseController(store: store, usageStore: nil, rememberSearches: false)
        await reuse.refreshRecents()
        let before = reuse.recentItems
        #expect(try await store.count() == 51)
        #expect(before.count == 50)
        #expect(before.contains { $0.id == fixture.victim.id } == insideRecentPage)
        let source = StoreRefreshSource(store: store)
        let search = PanelSearchModel(source: source)
        search.query = "syntheticpanelrefresh"
        await search.refresh()
        let selected = try #require(search.selectedItem)
        #expect(selected.id == fixture.victim.id)
        let preview = PanelPreviewModel()
        await preview.load(
            selected, loadMetadata: { try await store.item(id: $0) },
            loadContent: { try await store.content(for: $0) })
        #expect(preview.presentation(for: selected).text == PanelStoreFixture.body)
        let summary = try await RetentionEngine(store: store).runPurge(
            policy: RetentionPolicy(global: .never), now: fixture.now.addingTimeInterval(7200))
        #expect(summary.totalRowsPurged == 1)
        await reuse.refreshRecents()
        let recentChanged = before != reuse.recentItems
        #expect(recentChanged == insideRecentPage)
        await search.refreshAfterStoreChange(preview: preview)
        #expect(try await store.count() == 50)
        #expect(try await store.content(for: selected.id) == nil)
        #expect(search.filtered.isEmpty)
        #expect(search.selectedItem == nil)
        #expect(search.selection.selectedIDs.isEmpty)
        #expect(preview.presentation(for: selected).text == selected.preview)
        #expect(!preview.presentation(for: selected).isTextEditable)
        #expect(source.failedReads == 0)
    }
}

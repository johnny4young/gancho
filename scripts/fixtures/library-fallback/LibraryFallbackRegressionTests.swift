import Foundation
import GRDB
import GanchoAppCore
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@MainActor @Suite("Synthetic actual Library adapter fallback", .serialized)
struct LibraryFallbackRegressionTests {
    private func durable() throws -> GRDBClipboardStore {
        let root = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["GANCHO_SAFE_FIXTURE_ROOT"]!,
            isDirectory: true)
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(directory: root.appendingPathComponent(UUID().uuidString)))
        try store.migrate()
        return store
    }

    private func pair() -> [ClipItem] {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        return [
            ClipItem(
                createdAt: now, preview: "labneedle pinned", contentHash: "lab-pinned",
                isPinned: true),
            ClipItem(
                createdAt: now.addingTimeInterval(1), preview: "labneedle ordinary",
                contentHash: "lab-ordinary")
        ]
    }

    private func seed(_ rows: [ClipItem], into store: any ClipboardStore) async throws {
        for row in rows { try await store.insert(row, content: .text(row.preview)) }
    }

    @Test("RAM pinned search respects the same pinned-only scope as the durable adapter")
    func pinnedSearchScope() async throws {
        let rows = pair()
        let memory = InMemoryClipboardStore()
        let database = try durable()
        try await seed(rows, into: memory)
        try await seed(rows, into: database)
        let ram = AppModel(store: memory)
        let sql = AppModel(store: database, fullStore: database)
        let request = LibraryListRequest(scope: .pinned, text: "labneedle")
        let ramModel = LibraryClipListModel(fetch: ram.fetchLibraryClips)
        let sqlModel = LibraryClipListModel(fetch: sql.fetchLibraryClips)
        await ramModel.reload(request)
        await sqlModel.reload(request)
        #expect(sqlModel.items.map(\.id) == [rows[0].id])
        #expect(ramModel.items.map(\.id) == [rows[0].id])
        #expect(ramModel.failure == nil)
        try save(
            "pinned-search",
            [
                "ramCount": ramModel.items.count, "sqlCount": sqlModel.items.count,
                "ramContainsUnpinned": ramModel.items.contains { !$0.isPinned },
                "ramEnded": ramModel.reachedEnd
            ])
    }

    @Test("RAM scope controls: a small unsearched pinned scope and all-clips search work")
    func smallScopeControls() async throws {
        let rows = pair()
        let memory = InMemoryClipboardStore()
        try await seed(rows, into: memory)
        let app = AppModel(store: memory)
        let model = LibraryClipListModel(fetch: app.fetchLibraryClips)
        await model.reload(.pinned)
        #expect(model.items.map(\.id) == [rows[0].id])
        await model.reload(LibraryListRequest(scope: .allClips, text: "labneedle"))
        #expect(Set(model.items.map(\.id)) == Set(rows.map(\.id)))
        try save("small-scope-controls", ["allSearchCount": model.items.count])
    }

    private func longRows() -> [ClipItem] {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        return (0..<130).map { index -> ClipItem in
            let kind: ClipContentKind = index < 30 ? .url : .text
            let preview: String =
                index < 30
                ? "https://example.invalid/library/\(index)" : "synthetic library row \(index)"
            let date = base.addingTimeInterval(Double(index))
            let hash = "lab-row-\(index)"
            return ClipItem(
                createdAt: date, kind: kind, preview: preview,
                contentHash: hash, isPinned: index == 0)
        }
    }

    @Test("RAM kind filtering cannot declare EOF before older matching rows")
    func kindFilterBeforePaging() async throws {
        let rows = longRows()
        let memory = InMemoryClipboardStore()
        let database = try durable()
        try await seed(rows, into: memory)
        try await seed(rows, into: database)
        let app = AppModel(store: memory)
        let sql = AppModel(store: database, fullStore: database)
        let ramModel = LibraryClipListModel(fetch: app.fetchLibraryClips)
        let sqlModel = LibraryClipListModel(fetch: sql.fetchLibraryClips)
        let request = LibraryListRequest(scope: .allClips, kind: .links)
        await ramModel.reload(request)
        await ramModel.loadMore()
        await sqlModel.reload(request)
        #expect(sqlModel.items.count == 30)
        #expect(ramModel.items.count == 30)
        #expect(Set(ramModel.items.map(\.id)) == Set(sqlModel.items.map(\.id)))
        try save(
            "kind-paging",
            [
                "ramCount": ramModel.items.count, "sqlCount": sqlModel.items.count,
                "ramEnded": ramModel.reachedEnd, "memoryStoreCount": try await memory.count()
            ])
    }

    @Test("RAM pinned filtering cannot omit a pin older than the first unfiltered page")
    func pinnedFilterBeforePaging() async throws {
        let rows = longRows()
        let memory = InMemoryClipboardStore()
        try await seed(rows, into: memory)
        let app = AppModel(store: memory)
        let model = LibraryClipListModel(fetch: app.fetchLibraryClips)
        await model.reload(.pinned)
        await model.loadMore()
        #expect(model.items.map(\.id) == [rows[0].id])
        try save(
            "pinned-paging",
            [
                "ramCount": model.items.count, "ramEnded": model.reachedEnd,
                "memoryStoreCount": try await memory.count()
            ])
    }

    @Test("RAM unfiltered paging still reaches all 130 rows without duplicates")
    func unfilteredPagingControl() async throws {
        let rows = longRows()
        let memory = InMemoryClipboardStore()
        try await seed(rows, into: memory)
        let app = AppModel(store: memory)
        let model = LibraryClipListModel(fetch: app.fetchLibraryClips)
        await model.reload(.allClips)
        #expect(model.items.count == 100)
        #expect(!model.reachedEnd)
        await model.loadMore()
        #expect(model.items.count == 130)
        #expect(Set(model.items.map(\.id)).count == 130)
        #expect(model.reachedEnd)
        try save(
            "unfiltered-control",
            [
                "ramCount": model.items.count, "uniqueCount": Set(model.items.map(\.id)).count,
                "ramEnded": model.reachedEnd
            ])
    }

    private func save(_ label: String, _ value: [String: Any]) throws {
        let root = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["GANCHO_SAFE_FIXTURE_ROOT"]!,
            isDirectory: true)
        try JSONSerialization.data(withJSONObject: value, options: [.prettyPrinted, .sortedKeys])
            .write(to: root.appendingPathComponent(label + ".json"))
    }
}

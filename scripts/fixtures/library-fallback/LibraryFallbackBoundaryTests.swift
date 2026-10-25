import Foundation
import GRDB
import GanchoAppCore
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

private actor SnapshotStore: ClipboardStore {
    struct Read: Sendable, Equatable {
        let offset: Int
        let limit: Int
    }
    let rows: [ClipItem]
    private(set) var reads: [Read] = []
    private(set) var contentReads = 0
    nonisolated var isDurable: Bool { false }
    init(_ rows: [ClipItem]) { self.rows = rows }
    func items(offset: Int, limit: Int) async throws -> [ClipItem] {
        reads.append(Read(offset: offset, limit: limit))
        return Array(rows.dropFirst(max(offset, 0)).prefix(max(limit, 0)))
    }
    func count() async throws -> Int { rows.count }
    func content(for id: UUID) async throws -> ClipContent? {
        contentReads += 1
        return nil
    }
    func item(id: UUID) async throws -> ClipItem? { rows.first { $0.id == id } }
    func insert(_ item: ClipItem, content: ClipContent?) async throws -> ClipItem { item }
    func delete(id: UUID) async throws {}
    func exportJSON() async throws -> Data { Data() }
    func exportCSV() async throws -> Data { Data() }
}

@MainActor @Suite("Library RAM boundaries and backend parity", .serialized)
struct LibraryFallbackBoundaryTests {
    private static let count = 130

    private func row(_ index: Int) -> ClipItem {
        let id = UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index + 1))!
        let date = Date(timeIntervalSince1970: 1_800_000_000 + Double(index / 5))
        let kinds: [ClipContentKind] = [.url, .text, .code]
        return ClipItem(
            id: id, createdAt: date, kind: kinds[index % 3],
            title: index.isMultiple(of: 2) ? "Release" : "", preview: "Synthetic café row \(index)",
            contentHash: "boundary-row-\(index)", isPinned: index.isMultiple(of: 7))
    }

    private func data() -> [ClipItem] { (0..<Self.count).map(row) }

    private func memory(_ rows: [ClipItem]) async throws -> InMemoryClipboardStore {
        let store = InMemoryClipboardStore()
        // Deliberately unrelated to capture-time order, including tied dates.
        for item in rows.reversed() { try await store.insert(item, content: .text(item.preview)) }
        return store
    }

    private func database(_ rows: [ClipItem]) async throws -> GRDBClipboardStore {
        let root = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["GANCHO_SAFE_FIXTURE_ROOT"]!)
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(directory: root.appendingPathComponent(UUID().uuidString)))
        try store.migrate()
        for item in rows { try await store.insert(item, content: .text(item.preview)) }
        return store
    }

    // Independent index-domain oracle: fixture metadata is derived from these
    // integers, so the expected order does not invoke the product sorter/filter.
    private func expected(pinned: Bool, kind: ClipKindFilter, oldest: Bool) -> [UUID] {
        let indices = (0..<Self.count).filter { index in
            let matchesScope = !pinned || index.isMultiple(of: 7)
            let matchesKind =
                kind == .all || (kind == .links && index.isMultiple(of: 3))
                || (kind == .code && index % 3 == 2)
            return matchesScope && matchesKind
        }.sorted { left, right in
            if left.isMultiple(of: 7) != right.isMultiple(of: 7) { return left.isMultiple(of: 7) }
            if left / 5 != right / 5 { return oldest ? left / 5 < right / 5 : left / 5 > right / 5 }
            return oldest ? left < right : left > right
        }
        return indices.map { row($0).id }
    }

    @Test("Limits0/1/50 and offsets are applied after scope/kind/stable ordering")
    func pageBoundaryMatrix() async throws {
        let rows = data()
        let ram = AppModel(store: try await memory(rows))
        let sqlStore = try await database(rows)
        let sql = AppModel(store: sqlStore, fullStore: sqlStore)
        var comparisons = 0
        for pinned in [false, true] {
            for kind in [ClipKindFilter.all, .links, .code] {
                for oldest in [false, true] {
                    let request = LibraryListRequest(
                        scope: pinned ? .pinned : .allClips,
                        kind: kind, oldestFirst: oldest)
                    let ordered = expected(pinned: pinned, kind: kind, oldest: oldest)
                    for offset in [0, 1, 49, 50, 129, 130, 300] {
                        for limit in [0, 1, 50] {
                            let wanted = Array(ordered.dropFirst(offset).prefix(limit))
                            let memoryPage = try await ram.fetchLibraryClips(
                                request, offset: offset, limit: limit)
                            let sqlPage = try await sql.fetchLibraryClips(
                                request, offset: offset, limit: limit)
                            #expect(memoryPage.map(\.id) == wanted)
                            #expect(sqlPage.map(\.id) == wanted)
                            comparisons += 1
                        }
                    }
                }
            }
        }
        try save("boundary-matrix", ["pagePairs": comparisons, "limits": [0, 1, 50]])
    }

    @Test("Text/kind/pinned search combines predicates and folds case/accents")
    func combinedSearch() async throws {
        let rows = data()
        let ram = AppModel(store: try await memory(rows))
        let sqlStore = try await database(rows)
        let sql = AppModel(store: sqlStore, fullStore: sqlStore)
        for oldest in [false, true] {
            let request = LibraryListRequest(
                scope: .pinned, text: "CAFE release", kind: .links,
                oldestFirst: oldest)
            let wanted = expected(pinned: true, kind: .links, oldest: oldest).filter { id in
                let index = Int(id.uuidString.suffix(12))! - 1
                return index.isMultiple(of: 2)
            }
            let ramModel = LibraryClipListModel(fetch: ram.fetchLibraryClips)
            let sqlModel = LibraryClipListModel(fetch: sql.fetchLibraryClips)
            await ramModel.reload(request)
            await sqlModel.reload(request)
            #expect(ramModel.items.map(\.id) == wanted)
            #expect(sqlModel.items.map(\.id) == wanted)
        }
    }

    @Test("Unsupported scopes and zero limits do not read RAM; a page uses one metadata snapshot")
    func readBoundary() async throws {
        let source = SnapshotStore(data())
        let app = AppModel(store: source)
        let zero = try await app.fetchLibraryClips(.init(scope: .allClips), offset: 0, limit: 0)
        let board = try await app.fetchLibraryClips(
            .init(scope: .board(UUID())), offset: 0, limit: 50)
        let filter = try await app.fetchLibraryClips(
            .init(scope: .savedFilter(.init(name: "Synthetic unsupported"))), offset: 0, limit: 50)
        #expect(zero.isEmpty && board.isEmpty && filter.isEmpty)
        #expect(await source.reads.isEmpty)
        let page = try await app.fetchLibraryClips(.init(scope: .pinned), offset: 1, limit: 50)
        #expect(page.count == 18)
        #expect(await source.reads == [SnapshotStore.Read(offset: 0, limit: Int.max)])
        #expect(await source.contentReads == 0)
    }

    @Test("Recopy order and a new capture preserve stable cursor pages and true EOF")
    func pagingAfterMutation() async throws {
        let rows = data()
        let source = try await memory(rows)
        let app = AppModel(store: source)
        let model = LibraryClipListModel(fetch: app.fetchLibraryClips)
        await model.reload(.allClips)
        #expect(model.items.count == 100)
        #expect(!model.reachedEnd)
        try await source.insert(rows[42], content: .text(rows[42].preview))
        var added = row(130)
        added.createdAt = .distantFuture
        try await source.insert(added, content: .text(added.preview))
        await model.loadMore()
        #expect(model.items.count == 131)
        #expect(Set(model.items.map(\.id)).count == 131)
        #expect(Set(model.items.map(\.id)) == Set((rows + [added]).map(\.id)))
        #expect(model.reachedEnd)
        let second = try await app.fetchLibraryClips(
            .init(scope: .allClips), offset: 131, limit: 50)
        #expect(second.isEmpty)
    }

    @Test("Transfer of owned RAM fixtures to GRDB preserves IDs/content and request results")
    func fixtureBackendTransition() async throws {
        let rows = data()
        let memoryStore = try await memory(rows)
        let ram = AppModel(store: memoryStore)
        let captured = try await memoryStore.items(offset: 0, limit: Int.max)
        let sqlStore = try await database([])
        for item in captured {
            try await sqlStore.insert(item, content: try await memoryStore.content(for: item.id))
        }
        let sql = AppModel(store: sqlStore, fullStore: sqlStore)
        #expect(try await memoryStore.count() == 130)
        #expect(try await sqlStore.count() == 130)
        for item in captured {
            #expect(try await sqlStore.content(for: item.id) == .text(item.preview))
        }
        for scope in [LibraryClipScope.allClips, .pinned] {
            for oldest in [false, true] {
                let request = LibraryListRequest(scope: scope, kind: .links, oldestFirst: oldest)
                let before = try await ram.fetchLibraryClips(request, offset: 1, limit: 50)
                let after = try await sql.fetchLibraryClips(request, offset: 1, limit: 50)
                #expect(before.map(\.id) == after.map(\.id))
            }
        }
        try save(
            "fixture-transfer", ["ramRows": 130, "sqlRows": 130, "contentsChecked": captured.count])
    }

    @Test("Record synthetic metadata snapshot cost without a product performance threshold")
    func snapshotCostObservation() async throws {
        var samples: [[String: Any]] = []
        for size in [100, 1_000, 10_000] {
            let rows = (0..<size).map(row)
            for kind in [ClipKindFilter.all, .links] {
                let source = SnapshotStore(rows)
                let app = AppModel(store: source)
                for repetition in 0..<5 {
                    let start = ContinuousClock.now
                    let page = try await app.fetchLibraryClips(
                        .init(scope: .allClips, kind: kind), offset: 1, limit: 50)
                    let components = start.duration(to: .now).components
                    let seconds = Double(components.seconds) + Double(components.attoseconds) / 1e18
                    #expect(!page.isEmpty)
                    samples.append([
                        "size": size, "kind": kind == .all ? "all" : "links",
                        "repetition": repetition, "seconds": seconds,
                        "state": repetition == 0 ? "first-call-for-new-store" : "warm"
                    ])
                }
                #expect(await source.contentReads == 0)
            }
        }
        try save(
            "snapshot-cost",
            ["samples": samples, "scope": "Synthetic adapter only; no UI/render or absolute budget"]
        )
    }

    private func save(_ name: String, _ object: [String: Any]) throws {
        let root = URL(
            fileURLWithPath: ProcessInfo.processInfo.environment["GANCHO_SAFE_FIXTURE_ROOT"]!)
        try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
            .write(to: root.appendingPathComponent(name + ".json"))
    }
}

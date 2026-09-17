import Foundation
import Testing

@testable import GanchoKit

/// The `isDurable` flag drives the "your history isn't being saved" banner when
/// the encrypted store can't open and the app falls back to memory. It's read
/// off `any ClipboardStore`, so the existential must dispatch to the override.
@Suite("Store durability flag")
struct ClipboardStoreDurabilityTests {
    @Test("The in-memory fallback reports itself as non-durable")
    func inMemoryIsEphemeral() {
        #expect(InMemoryClipboardStore().isDurable == false)
        let erased: any ClipboardStore = InMemoryClipboardStore()
        #expect(erased.isDurable == false, "existential dispatch must see the override")
    }

    @Test("A real GRDB store is durable")
    func grdbIsDurable() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = try GRDBClipboardStore(directory: dir)
        #expect(store.isDurable == true)
        let erased: any ClipboardStore = store
        #expect(erased.isDurable == true)
    }

    @Test("item(id:) reads through the existential on the in-memory fallback")
    func inMemoryKeyedRead() async throws {
        let erased: any ClipboardStore = InMemoryClipboardStore()
        let inserted = try await erased.insert(
            ClipItem(preview: "look me up", contentHash: "look-me-up"), content: .text("look me up")
        )
        #expect(try await erased.item(id: inserted.id)?.id == inserted.id)
        #expect(try await erased.item(id: UUID()) == nil)
        try await erased.delete(id: inserted.id)
        #expect(try await erased.item(id: inserted.id) == nil, "a deleted clip reads as gone")
    }

    @Test("item(id:) on GRDB is the keyed read, archived rows included as gone")
    func grdbKeyedRead() async throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let erased: any ClipboardStore = try GRDBClipboardStore(directory: dir)
        let inserted = try await erased.insert(
            ClipItem(preview: "look me up", contentHash: "look-me-up"), content: .text("look me up")
        )
        #expect(try await erased.item(id: inserted.id)?.id == inserted.id)
        try await erased.delete(id: inserted.id)
        #expect(try await erased.item(id: inserted.id) == nil)
    }

    @Test("The default item(id:) walks every page for a store without a keyed read")
    func defaultWalksPages() async throws {
        let store = PagedOnlyStore(rows: (1...450).map { ClipItem(preview: "row \($0)") })
        let wanted = await store.rows[420]
        let erased: any ClipboardStore = store
        #expect(try await erased.item(id: wanted.id)?.id == wanted.id)
        #expect(try await erased.item(id: UUID()) == nil)
    }
}

/// A conformer that only knows how to page — the shape of the test doubles
/// in GanchoAppCoreTests — so the protocol default is what serves `item(id:)`.
private actor PagedOnlyStore: ClipboardStore {
    var rows: [ClipItem]
    init(rows: [ClipItem]) { self.rows = rows }
    nonisolated var isDurable: Bool { false }
    func items(offset: Int, limit: Int) async throws -> [ClipItem] {
        Array(rows.dropFirst(offset).prefix(limit))
    }
    func count() async throws -> Int { rows.count }
    func delete(id: UUID) async throws { rows.removeAll { $0.id == id } }
    func content(for id: UUID) async throws -> ClipContent? { nil }
    func exportJSON() async throws -> Data { Data() }
    func exportCSV() async throws -> Data { Data() }
    @discardableResult
    func insert(_ item: ClipItem, content: ClipContent?) async throws -> ClipItem {
        rows.insert(item, at: 0)
        return item
    }
}

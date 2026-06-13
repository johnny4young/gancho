import Foundation
import GRDB
import Testing

@testable import GanchoKit

@Suite("Pins & pinboards")
struct PinboardTests {
    private func makeStore() throws -> GRDBClipboardStore {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("pin-\(UUID().uuidString)")))
        try store.migrate()
        return store
    }

    @Test("Pinning floats the item above newer history")
    func pinFloats() async throws {
        let store = try makeStore()
        let old = ClipItem(
            createdAt: Date(timeIntervalSince1970: 1), lastUsedAt: Date(timeIntervalSince1970: 1),
            preview: "old", contentHash: "h1")
        let new = ClipItem(preview: "new", contentHash: "h2")
        try await store.insert(old, content: .text("old"))
        try await store.insert(new, content: .text("new"))

        try await store.setPinned(id: old.id, true)
        #expect(try await store.items().first?.preview == "old")
        #expect(try await store.pinnedCount() == 1)
    }

    @Test("Board CRUD: create, list ordered, delete returns clips to history")
    func boardCRUD() async throws {
        let store = try makeStore()
        let work = try await store.createPinboard(name: "Work")
        _ = try await store.createPinboard(name: "Colors")
        #expect(try await store.pinboards().map(\.name) == ["Work", "Colors"])

        let item = ClipItem(preview: "clip", contentHash: "h")
        try await store.insert(item, content: .text("clip"))
        try await store.assign(clipID: item.id, toBoard: work.id)
        #expect(try await store.items(inBoard: work.id).map(\.preview) == ["clip"])
        // Assignment implies pinned (board members survive retention).
        #expect(try await store.pinnedCount() == 1)

        try await store.deletePinboard(id: work.id)
        #expect(try await store.pinboards().count == 1)
        #expect(try await store.count() == 1, "clips must survive board deletion")
    }

    @Test("Manual reorder drives board ordering")
    func manualReorder() async throws {
        let store = try makeStore()
        let board = try await store.createPinboard(name: "Ordered")
        let first = ClipItem(preview: "first", contentHash: "h1")
        let second = ClipItem(preview: "second", contentHash: "h2")
        try await store.insert(first, content: .text("first"))
        try await store.insert(second, content: .text("second"))
        try await store.assign(clipID: first.id, toBoard: board.id)
        try await store.assign(clipID: second.id, toBoard: board.id)

        try await store.setSortIndex(clipID: second.id, 0)
        try await store.setSortIndex(clipID: first.id, 1)
        #expect(
            try await store.items(inBoard: board.id).map(\.preview) == ["second", "first"])
    }

    @Test("Free limits: 10 pins, 1 board; Pro unlimited")
    func freeLimits() {
        #expect(PinLimits.canPin(currentPinCount: 9, isPro: false))
        #expect(!PinLimits.canPin(currentPinCount: 10, isPro: false))
        #expect(PinLimits.canPin(currentPinCount: 10_000, isPro: true))
        #expect(PinLimits.canCreatePinboard(currentBoardCount: 0, isPro: false))
        #expect(!PinLimits.canCreatePinboard(currentBoardCount: 1, isPro: false))
        #expect(PinLimits.canCreatePinboard(currentBoardCount: 50, isPro: true))
    }
}

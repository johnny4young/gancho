import Foundation
import GRDB
import Testing

@testable import GanchoKit

@Suite("Boards & pins")
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

    @Test("Board CRUD: create with glyph, list, rename, delete returns clips to history")
    func boardCRUD() async throws {
        let store = try makeStore()
        let work = try await store.createPinboard(name: "Work", sfSymbol: "briefcase")
        _ = try await store.createPinboard(name: "Colors")
        // The seeded Favorites board is excluded from the user-board assertions.
        #expect(
            try await store.pinboards().filter { !$0.isSystem }.map(\.name) == ["Work", "Colors"])
        #expect(
            try await store.pinboards().first(where: { $0.name == "Work" })?.sfSymbol == "briefcase"
        )

        let item = ClipItem(preview: "clip", contentHash: "h")
        try await store.insert(item, content: .text("clip"))
        try await store.assign(clipID: item.id, toBoard: work.id)
        #expect(try await store.items(inBoard: work.id).map(\.preview) == ["clip"])
        #expect(try await store.count(inBoard: work.id) == 1)
        // Board membership is orthogonal to pinning — assigning does NOT pin.
        #expect(try await store.pinnedCount() == 0)

        try await store.renameBoard(id: work.id, name: "Job")
        #expect(
            try await store.pinboards().filter { !$0.isSystem }.map(\.name) == ["Job", "Colors"])

        try await store.deletePinboard(id: work.id)
        #expect(try await store.pinboards().filter { !$0.isSystem }.count == 1)
        #expect(try await store.count() == 1, "clips must survive board deletion")
        #expect(try await store.items(inBoard: work.id).isEmpty, "membership cascades away")
    }

    @Test("Favorites is a built-in board: present, first, immutable")
    func favoritesBoard() async throws {
        let store = try makeStore()
        // Seeded by migration — present before any user board exists.
        #expect(try await store.pinboards().first?.id == Pinboard.favoritesID)
        #expect(try await store.pinboards().first?.isSystem == true)

        // A user board never displaces Favorites from the top.
        _ = try await store.createPinboard(name: "Work")
        #expect(try await store.pinboards().first?.id == Pinboard.favoritesID)

        // Rename and delete are no-ops on it.
        try await store.renameBoard(id: Pinboard.favoritesID, name: "Hacked")
        try await store.deletePinboard(id: Pinboard.favoritesID)
        let favorite = try await store.pinboards().first { $0.id == Pinboard.favoritesID }
        #expect(favorite?.name == "Favorites")
    }

    @Test("A clip can belong to many boards; assign is idempotent, unassign is per-board")
    func multiMembership() async throws {
        let store = try makeStore()
        let a = try await store.createPinboard(name: "A")
        let b = try await store.createPinboard(name: "B")
        let item = ClipItem(preview: "shared", contentHash: "h")
        try await store.insert(item, content: .text("shared"))

        try await store.assign(clipID: item.id, toBoard: a.id)
        try await store.assign(clipID: item.id, toBoard: a.id)  // idempotent
        try await store.assign(clipID: item.id, toBoard: b.id)
        #expect(try await store.boardIDs(forClip: item.id) == Set([a.id, b.id]))
        #expect(try await store.count(inBoard: a.id) == 1)

        try await store.unassign(clipID: item.id, fromBoard: a.id)
        #expect(try await store.boardIDs(forClip: item.id) == Set([b.id]))

        try await store.removeFromAllBoards(clipID: item.id)
        #expect(try await store.boardIDs(forClip: item.id).isEmpty)
    }

    @Test("Changing membership re-queues the clip for sync (membership rides the record)")
    func membershipReuploadsClip() async throws {
        let store = try makeStore()
        let board = try await store.createPinboard(name: "Sync me")
        let item = ClipItem(preview: "x", contentHash: "h")
        try await store.insert(item, content: .text("x"))
        // Settle the clip as already uploaded, so the upload FLAG — not the
        // NULL system fields of a never-synced row — is what we observe.
        try await store.markUploaded(id: item.id, systemFields: Data([1]))
        #expect(try await store.pendingUploads().isEmpty)

        try await store.assign(clipID: item.id, toBoard: board.id)
        #expect(
            try await store.pendingUploads().contains { $0.item.id == item.id },
            "assigning to a board re-queues the clip")

        try await store.markUploaded(id: item.id, systemFields: Data([2]))
        try await store.removeFromAllBoards(clipID: item.id)
        #expect(
            try await store.pendingUploads().contains { $0.item.id == item.id },
            "removing from boards re-queues the clip too")
    }

    @Test("Board members survive retention even though they are not pinned")
    func boardMembersExemptFromRetention() async throws {
        let store = try makeStore()
        let board = try await store.createPinboard(name: "Keep")
        let now = Date(timeIntervalSince1970: 10_000_000)
        let stale = ClipItem(
            createdAt: now.addingTimeInterval(-2 * 86_400),
            lastUsedAt: now.addingTimeInterval(-2 * 86_400),
            preview: "stale", contentHash: "h")
        try await store.insert(stale, content: .text("stale"))
        try await store.assign(clipID: stale.id, toBoard: board.id)

        try await RetentionEngine(store: store)
            .runPurge(policy: RetentionPolicy(global: .day), now: now)
        #expect(try await store.count(inBoard: board.id) == 1, "board members never expire")
    }

    @Test("Synced membership rebuilds boards and seeds a placeholder for unknown ids")
    func setBoardMembershipRebuilds() async throws {
        let store = try makeStore()
        let known = try await store.createPinboard(name: "Known")
        let item = ClipItem(preview: "clip", contentHash: "h")
        try await store.insert(item, content: .text("clip"))

        // A synced clip references a known board + an id whose metadata hasn't
        // arrived: membership is kept and the unknown board gets a placeholder.
        let unknown = UUID()
        try await store.setBoardMembership(clipID: item.id, boardIDs: [known.id, unknown])
        #expect(try await store.boardIDs(forClip: item.id) == Set([known.id, unknown]))
        #expect(try await store.pinboards().contains { $0.id == unknown })

        // Re-applying replaces (it doesn't accumulate).
        try await store.setBoardMembership(clipID: item.id, boardIDs: [known.id])
        #expect(try await store.boardIDs(forClip: item.id) == Set([known.id]))
    }

    @Test("Board metadata uploads once; an incoming record clears the flag")
    func boardMetadataSync() async throws {
        let store = try makeStore()
        let board = try await store.createPinboard(name: "Work", sfSymbol: "briefcase")
        // A freshly created board is pending upload.
        #expect(try await store.pendingBoardUploads().contains { $0.id == board.id })

        try await store.markBoardUploaded(id: board.id, systemFields: Data([1, 2, 3]))
        #expect(!(try await store.pendingBoardUploads().contains { $0.id == board.id }))
        #expect(try await store.boardSystemFields(for: board.id) == Data([1, 2, 3]))

        // An incoming board record upserts metadata without re-flagging upload.
        let incoming = Pinboard(name: "From another device", sfSymbol: "star")
        try await store.applyRemoteBoardUpsert(incoming, systemFields: Data([9]))
        #expect(try await store.pinboards().map(\.name).contains("From another device"))
        #expect(!(try await store.pendingBoardUploads().contains { $0.id == incoming.id }))
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

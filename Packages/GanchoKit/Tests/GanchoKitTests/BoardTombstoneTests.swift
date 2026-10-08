import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("Pending board deletions reject remote resurrection")
struct BoardTombstoneTests {
    private func makeStore() throws -> GRDBClipboardStore {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("board-tombstone-\(UUID().uuidString)")))
        try store.migrate()
        return store
    }

    @Test("Incoming board metadata cannot resurrect a pending local deletion")
    func metadataDoesNotResurrectDeletedBoard() async throws {
        let store = try makeStore()
        let board = try await store.createPinboard(name: "Deleted")
        try await store.markBoardUploaded(id: board.id, systemFields: Data([1]))
        try await store.deletePinboard(id: board.id)

        try await store.applyRemoteBoardUpsert(board, systemFields: Data([2]))

        #expect(try await store.pinboards().contains { $0.id == board.id } == false)
        #expect(try await store.boardSystemFields(for: board.id) == nil)
        #expect(try await store.pendingBoardUploads().contains { $0.id == board.id } == false)
        #expect(try await store.pendingBoardDeletionRecordIDs() == [board.id.uuidString])
    }

    @Test("Synced membership ignores deleted boards but preserves other memberships")
    func membershipDoesNotResurrectDeletedBoard() async throws {
        let store = try makeStore()
        let deleted = try await store.createPinboard(name: "Deleted")
        let known = try await store.createPinboard(name: "Known")
        let unknown = UUID()
        let clip = ClipItem(preview: "body", contentHash: "membership")
        try await store.insert(clip, content: .text("body"))
        try await store.assign(clipID: clip.id, toBoard: deleted.id)
        try await store.deletePinboardForSync(id: deleted.id)

        try await store.setBoardMembership(
            clipID: clip.id, boardIDs: [deleted.id, known.id, unknown, Pinboard.favoritesID])

        #expect(
            try await store.boardIDs(forClip: clip.id)
                == Set([known.id, unknown, Pinboard.favoritesID]))
        #expect(try await store.pinboards().contains { $0.id == deleted.id } == false)
        #expect(try await store.pinboards().first { $0.id == unknown }?.name.isEmpty == true)
        #expect(try await store.pendingBoardDeletionRecordIDs() == [deleted.id.uuidString])

        // Replacing membership with only the deleted id still clears prior members.
        try await store.setBoardMembership(clipID: clip.id, boardIDs: [deleted.id])
        #expect(try await store.boardIDs(forClip: clip.id).isEmpty)
    }

    @Test("A fetched page skips deleted board metadata without losing its arriving clip")
    func pageDoesNotResurrectDeletedBoard() async throws {
        let store = try makeStore()
        let deleted = try await store.createPinboard(name: "Deleted")
        try await store.deletePinboardForSync(id: deleted.id)
        let arriving = Pinboard(name: "Arriving")
        let clip = ClipItem(preview: "body", contentHash: "page")

        let summary = try await store.applyRemoteChanges(
            clips: [
                RemoteClipChange(
                    item: clip, content: .text("body"), systemFields: Data([1]),
                    boardIDs: [deleted.id, arriving.id])
            ],
            boards: [
                RemoteBoardChange(board: deleted, systemFields: Data([2])),
                RemoteBoardChange(board: arriving, systemFields: Data([3]))
            ],
            clipDeletions: [], boardDeletions: [])

        #expect(summary == RemoteApplySummary(applied: 2, skippedAsStale: 1, failed: 0))
        #expect(try await store.content(for: clip.id) == .text("body"))
        #expect(try await store.boardIDs(forClip: clip.id) == [arriving.id])
        // The server copy still names the deleted board, so the clip re-uploads.
        #expect(try await store.pendingUploadIDs() == [clip.id])
        #expect(try await store.pinboards().contains { $0.id == deleted.id } == false)
        #expect(try await store.pinboards().first { $0.id == arriving.id }?.name == "Arriving")
        #expect(try await store.pendingBoardDeletionRecordIDs() == [deleted.id.uuidString])
    }

    @Test("Acknowledging deletion releases the temporary guard for future remote records")
    func acknowledgedDeletionDoesNotPermanentlyBlockTheID() async throws {
        let store = try makeStore()
        let board = try await store.createPinboard(name: "Deleted")
        let clip = ClipItem(preview: "body", contentHash: "acknowledged")
        try await store.insert(clip, content: .text("body"))
        try await store.deletePinboardForSync(id: board.id)
        try await store.clearBoardTombstone(recordID: board.id.uuidString)

        try await store.setBoardMembership(clipID: clip.id, boardIDs: [board.id])
        try await store.applyRemoteBoardUpsert(board, systemFields: Data([4]))

        #expect(try await store.pendingBoardDeletionRecordIDs().isEmpty)
        #expect(try await store.boardIDs(forClip: clip.id) == [board.id])
        #expect(try await store.pinboards().first { $0.id == board.id }?.name == "Deleted")
        #expect(try await store.boardSystemFields(for: board.id) == Data([4]))
    }
}

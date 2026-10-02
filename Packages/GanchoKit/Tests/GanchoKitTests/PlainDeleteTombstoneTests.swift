import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("Plain deletes keep tombstones for rows that ever synced")
struct PlainDeleteTombstoneTests {
    private func makeStore() throws -> GRDBClipboardStore {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("plain-delete-\(UUID().uuidString)")))
        try store.migrate()
        return store
    }

    @Test("A plain delete still tombstones a clip that ever synced, and only that clip")
    func plainDeleteTombstonesSyncedClips() async throws {
        let store = try makeStore()
        let synced = ClipItem(preview: "synced", contentHash: "hs")
        let local = ClipItem(preview: "local", contentHash: "hl")
        try await store.insert(synced, content: .text("synced"))
        try await store.insert(local, content: .text("local"))
        try await store.markUploaded(id: synced.id, systemFields: Data([1]))

        try await store.delete(id: synced.id)
        try await store.delete(id: local.id)

        #expect(try await store.count() == 0)
        #expect(try await store.pendingDeletionRecordIDs() == [synced.id.uuidString])
    }

    @Test("A plain board delete still tombstones a board that ever synced")
    func plainBoardDeleteTombstonesSyncedBoards() async throws {
        let store = try makeStore()
        let synced = try await store.createPinboard(name: "Synced")
        let local = try await store.createPinboard(name: "Local")
        try await store.markBoardUploaded(id: synced.id, systemFields: Data([1]))

        try await store.deletePinboard(id: synced.id)
        try await store.deletePinboard(id: local.id)

        let remaining = try await store.pinboards().map(\.id)
        #expect(!remaining.contains(synced.id) && !remaining.contains(local.id))
        #expect(try await store.pendingBoardDeletionRecordIDs() == [synced.id.uuidString])
    }
}

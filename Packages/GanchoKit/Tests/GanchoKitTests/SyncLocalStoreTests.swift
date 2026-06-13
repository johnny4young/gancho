import Foundation
import GRDB
import Testing

@testable import GanchoKit

@Suite("SyncLocalStore bridge — uploads, remote apply, tombstones")
struct SyncLocalStoreTests {
    private func makeStore() throws -> GRDBClipboardStore {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("sync-\(UUID().uuidString)")))
        try store.migrate()
        return store
    }

    @Test("New clips are pending upload until marked, then drop out")
    func pendingThenUploaded() async throws {
        let store = try makeStore()
        let item = ClipItem(preview: "hi", contentHash: "h")
        try await store.insert(item, content: .text("hi"))

        var pending = try await store.pendingUploads()
        #expect(pending.map(\.item.id) == [item.id])
        #expect(pending.first?.content == .text("hi"))

        try await store.markUploaded(id: item.id, systemFields: Data([1, 2, 3]))
        pending = try await store.pendingUploads()
        #expect(pending.isEmpty)
        #expect(try await store.systemFields(for: item.id) == Data([1, 2, 3]))
    }

    @Test("A local edit re-flags the clip for upload")
    func editReflags() async throws {
        let store = try makeStore()
        let item = ClipItem(preview: "v1", contentHash: "h")
        try await store.insert(item, content: .text("v1"))
        try await store.markUploaded(id: item.id, systemFields: Data([9]))
        #expect(try await store.pendingUploads().isEmpty)

        try await store.markNeedsUpload(id: item.id)
        #expect(try await store.pendingUploads().map(\.item.id) == [item.id])
    }

    @Test("Remote upsert applies a newer remote, ignores an older one")
    func remoteUpsertLastWriterWins() async throws {
        let store = try makeStore()
        let base = Date(timeIntervalSince1970: 1_000_000)
        let local = ClipItem(
            updatedAt: base, preview: "local", contentHash: "h", isPinned: false)
        try await store.insert(local, content: .text("local"))

        // Older remote → ignored, but its system fields are recorded.
        let older = ClipItem(
            id: local.id, updatedAt: base.addingTimeInterval(-60), preview: "older remote",
            contentHash: "h")
        try await store.applyRemoteUpsert(older, content: .text("older"), systemFields: Data([7]))
        #expect(try await store.items().first?.preview == "local")
        #expect(try await store.systemFields(for: local.id) == Data([7]))

        // Newer remote → wins.
        let newer = ClipItem(
            id: local.id, updatedAt: base.addingTimeInterval(60), preview: "newer remote",
            contentHash: "h")
        try await store.applyRemoteUpsert(newer, content: .text("newer"), systemFields: Data([8]))
        #expect(try await store.items().first?.preview == "newer remote")
        #expect(try await store.content(for: local.id) == .text("newer"))
    }

    @Test("Remote upsert of an unseen clip inserts it, not pending re-upload")
    func remoteUpsertInserts() async throws {
        let store = try makeStore()
        let remote = ClipItem(preview: "from other device", contentHash: "hr")
        try await store.applyRemoteUpsert(
            remote, content: .text("from other device"), systemFields: Data([1]))
        #expect(try await store.count() == 1)
        #expect(try await store.pendingUploads().isEmpty, "remote-applied rows are not dirty")
    }

    @Test("Deletes become tombstones, propagate, then clear")
    func deletionTombstones() async throws {
        let store = try makeStore()
        let item = ClipItem(preview: "doomed", contentHash: "h")
        try await store.insert(item, content: .text("doomed"))

        try await store.deleteForSync(id: item.id)
        #expect(try await store.count() == 0)
        #expect(try await store.pendingDeletionRecordIDs() == [item.id.uuidString])

        try await store.clearTombstone(recordID: item.id.uuidString)
        #expect(try await store.pendingDeletionRecordIDs().isEmpty)
    }

    @Test("Remote deletion removes the local row")
    func remoteDeletion() async throws {
        let store = try makeStore()
        let item = ClipItem(preview: "x", contentHash: "h")
        try await store.insert(item, content: .text("x"))
        try await store.applyRemoteDeletion(recordID: item.id.uuidString)
        #expect(try await store.count() == 0)
    }
}

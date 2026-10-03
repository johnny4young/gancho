import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("Remote sync applies reclaim blobs they orphan")
struct RemoteApplyBlobCleanupTests {
    private let blobDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("remote-blobs-\(UUID().uuidString)", isDirectory: true)

    private func makeStore() throws -> GRDBClipboardStore {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(), blobs: BlobStore(directory: blobDir))
        try store.migrate()
        return store
    }

    private func blobFiles() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: blobDir.path)) ?? [])
            .filter { $0 != "thumbnails" && !$0.hasPrefix(".") }
    }

    private func image(_ seed: String, updatedAt: Date = .now) -> (ClipItem, ClipContent) {
        let data = Data("remote-blob-\(seed)".utf8)
        let item = ClipItem(
            updatedAt: updatedAt, kind: .image, preview: "Image",
            contentHash: ClipItem.hash(of: data, kind: .image))
        return (item, .binary(data: data, typeIdentifier: "public.data"))
    }

    @Test("A remote deletion in a page removes the deleted clip's blob")
    func pageDeletionRemovesBlob() async throws {
        defer { try? FileManager.default.removeItem(at: blobDir) }
        let store = try makeStore()
        let (item, content) = image("page")
        try await store.insert(item, content: content)
        #expect(blobFiles().count == 1)

        _ = try await store.applyRemoteChanges(
            clips: [], boards: [], clipDeletions: [item.id.uuidString], boardDeletions: [])

        #expect(blobFiles().isEmpty)
    }

    @Test("A single remote deletion removes the deleted clip's blob")
    func singleDeletionRemovesBlob() async throws {
        defer { try? FileManager.default.removeItem(at: blobDir) }
        let store = try makeStore()
        let (item, content) = image("single")
        try await store.insert(item, content: content)

        try await store.applyRemoteDeletion(recordID: item.id.uuidString)

        #expect(blobFiles().isEmpty)
    }

    @Test("A winning remote replacement removes the blob it replaced")
    func replacementRemovesOldBlob() async throws {
        defer { try? FileManager.default.removeItem(at: blobDir) }
        let store = try makeStore()
        let (item, content) = image("old", updatedAt: Date(timeIntervalSince1970: 1))
        try await store.insert(item, content: content)
        var remote = item
        remote.updatedAt = Date(timeIntervalSince1970: 2)
        remote.kind = .text

        let change = RemoteClipChange(
            item: remote, content: .text("now text"), systemFields: Data([1]), boardIDs: [])
        _ = try await store.applyRemoteChanges(
            clips: [change], boards: [], clipDeletions: [], boardDeletions: [])

        #expect(try await store.content(for: item.id) == .text("now text"))
        #expect(blobFiles().isEmpty)
    }

    @Test("A stale remote binary does not leave its freshly written blob behind")
    func staleRemoteBlobIsReclaimed() async throws {
        defer { try? FileManager.default.removeItem(at: blobDir) }
        let store = try makeStore()
        let local = ClipItem(
            updatedAt: Date(timeIntervalSince1970: 10), preview: "t", contentHash: "t")
        try await store.insert(local, content: .text("t"))
        var (remote, content) = image("stale", updatedAt: Date(timeIntervalSince1970: 5))
        remote.id = local.id

        let won = try await store.applyRemoteUpsert(
            remote, content: content, systemFields: Data([1]))

        #expect(!won)
        #expect(blobFiles().isEmpty)
    }

    @Test("The maintenance sweep spares fresh unreferenced blobs and removes old ones")
    func sweepIsAgeGated() async throws {
        defer { try? FileManager.default.removeItem(at: blobDir) }
        let store = try makeStore()
        let blobs = BlobStore(directory: blobDir)
        let old = try blobs.write(Data("orphan-old".utf8))
        let fresh = try blobs.write(Data("orphan-fresh".utf8))
        try FileManager.default.setAttributes(
            [.modificationDate: Date.now.addingTimeInterval(-7_200)],
            ofItemAtPath: blobDir.appendingPathComponent(old).path)

        let removed = try await store.removeOrphanedBlobs(
            olderThan: .now.addingTimeInterval(-3_600))

        #expect(removed == 1)
        #expect(blobFiles() == [fresh])
    }
}

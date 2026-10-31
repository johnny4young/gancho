import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("Secrets stay local — sync never touches a sensitive clip")
struct SyncLocalSecretsTests {
    private func makeStore() throws -> GRDBClipboardStore {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("secrets-\(UUID().uuidString)")))
        try store.migrate()
        return store
    }

    @Test("A secret never uploads, even after a sync reset or an edit")
    func secretNeverUploads() async throws {
        let store = try makeStore()
        let secret = ClipItem(
            kind: .secret, preview: "●●●● 4Q2v", contentHash: "s", isSensitive: true)
        try await store.insert(secret, content: .text("AKIAIOSFODNN7EXAMPLE"))
        try await store.markNeedsUpload(id: secret.id)
        try await store.forgetAllSyncFields()

        #expect(try await store.pendingUploads().isEmpty)
        #expect(try await store.pendingUploadCount() == 0)
        #expect(try await store.pendingUploadIDs().isEmpty)
        #expect(try await store.pendingUpload(id: secret.id) == nil)
        #expect(try await store.isAwaitingUpload(id: secret.id) == false)
    }

    @Test("A remote secret never lands, and a remote change never touches a local secret")
    func remoteNeverTouchesSecrets() async throws {
        let store = try makeStore()
        let base = Date(timeIntervalSince1970: 1_000_000)
        let remoteSecret = ClipItem(
            updatedAt: base, kind: .secret, preview: "●●●● 4Q2v", contentHash: "r",
            isSensitive: true)
        #expect(
            try await store.applyRemoteUpsert(
                remoteSecret, content: .text("remote key"), systemFields: Data([1])) == false)
        #expect(try await store.items().isEmpty)

        let local = ClipItem(
            updatedAt: base, kind: .secret, preview: "●●●● 9Zx1", contentHash: "l",
            isSensitive: true)
        try await store.insert(local, content: .text("local key"))
        let newer = ClipItem(
            id: local.id, updatedAt: base.addingTimeInterval(60), preview: "plain",
            contentHash: "p")
        #expect(
            try await store.applyRemoteUpsert(
                newer, content: .text("plain"), systemFields: Data([2])) == false)
        #expect(try await store.content(for: local.id) == .text("local key"))
        #expect(try await store.systemFields(for: local.id) == nil)

        try await store.applyRemoteDeletion(recordID: local.id.uuidString)
        let summary = try await store.applyRemoteChanges(
            clips: [], boards: [], clipDeletions: [local.id.uuidString], boardDeletions: [])
        #expect(summary.failed == 0)
        #expect(try await store.content(for: local.id) == .text("local key"))
    }

    @Test("A remote secret writes no blob and is queued to leave iCloud")
    func remoteSecretLeavesNoBlobAndIsRetracted() async throws {
        let blobs = FileManager.default.temporaryDirectory
            .appendingPathComponent("secrets-blobs-\(UUID().uuidString)")
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(), blobs: BlobStore(directory: blobs))
        try store.migrate()
        defer { try? FileManager.default.removeItem(at: blobs) }
        let plain = ClipItem(preview: "kept", contentHash: "k")
        try await store.insert(plain, content: .text("kept"))
        let image = ClipItem(kind: .image, contentHash: "i", isSensitive: true)
        let text = ClipItem(kind: .secret, contentHash: "t", isSensitive: true)
        let collidingWithPlain = ClipItem(
            id: plain.id, updatedAt: .now.addingTimeInterval(60), kind: .secret,
            contentHash: "c", isSensitive: true)

        let summary = try await store.applyRemoteChanges(
            clips: [
                RemoteClipChange(
                    item: image,
                    content: .binary(
                        data: Data(repeating: 7, count: 64),
                        typeIdentifier: "public.png"), systemFields: Data([1]), boardIDs: []),
                RemoteClipChange(
                    item: collidingWithPlain, content: .text("key"), systemFields: Data([3]),
                    boardIDs: [])
            ], boards: [], clipDeletions: [], boardDeletions: [])
        _ = try await store.applyRemoteUpsert(text, content: .text("key"), systemFields: Data([2]))

        #expect(summary.skippedAsStale == 2 && summary.failed == 0)
        #expect(try await store.items().map(\.id) == [plain.id])
        #expect(try await store.content(for: plain.id) == .text("kept"))
        let tombstones = Set(try await store.pendingDeletionRecordIDs())
        #expect(tombstones == [image.id.uuidString, text.id.uuidString])
        let files = FileManager.default.enumerator(
            at: blobs, includingPropertiesForKeys: [.isRegularFileKey],
            options: .skipsHiddenFiles)?.compactMap { $0 as? URL }
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
        #expect(files?.isEmpty ?? true, "no secret bytes reach the blob store")
    }
}

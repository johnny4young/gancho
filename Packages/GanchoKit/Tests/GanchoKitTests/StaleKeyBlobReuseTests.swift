import Foundation
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

private func tempDir() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("gancho-stale-key-\(UUID().uuidString)", isDirectory: true)
}

@Suite("BlobStore — a sealed file left under another key")
struct StaleKeyBlobReuseTests {
    private static let payload = Data("stale-key-fixture".utf8) + Data([0, 1, 2, 3])

    @Test("Writing identical bytes under a new key leaves the blob readable")
    func rewriteUnderNewKeyIsReadable() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let oldKey = BlobStore.encryptionKeyData(for: try KeychainPassphraseStore.generateKey())
        let newKey = BlobStore.encryptionKeyData(for: try KeychainPassphraseStore.generateKey())

        try BlobStore(directory: dir, encryptionKeyData: oldKey).write(Self.payload)
        let current = BlobStore(directory: dir, encryptionKeyData: newKey)
        let hash = try current.write(Self.payload)

        #expect(try current.read(hash: hash) == Self.payload)
    }

    #if SQLITE_HAS_CODEC
        @Test("A database reset that keeps blobs/ still yields preparable uploads")
        func pendingUploadSurvivesDatabaseOnlyReset() async throws {
            let dir = tempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let content = ClipContent.binary(data: Self.payload, typeIdentifier: "public.data")
            let hash = ClipItem.hash(of: Self.payload, kind: .image)

            var old: GRDBClipboardStore? = try GRDBClipboardStore(
                directory: dir, passphrase: try KeychainPassphraseStore.generateKey())
            try await old?.insert(
                ClipItem(kind: .image, preview: "Image", contentHash: hash), content: content)
            old = nil
            // Before stores archived whole generations, recovery moved only the
            // database files aside and left blobs/ in the live namespace.
            for name in ["gancho.sqlite", "gancho.sqlite-wal", "gancho.sqlite-shm"] {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
            }

            let store = try GRDBClipboardStore(
                directory: dir, passphrase: try KeychainPassphraseStore.generateKey())
            let item = try await store.insert(
                ClipItem(kind: .image, preview: "Image", contentHash: hash), content: content)

            let pending = try await store.pendingUpload(id: item.id)
            #expect(pending?.content == content)
        }
    #endif
}

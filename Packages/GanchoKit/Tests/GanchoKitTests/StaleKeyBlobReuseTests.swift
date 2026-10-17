import Foundation
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

private func tempDir() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("gancho-stale-key-\(UUID().uuidString)", isDirectory: true)
}

private func freshKeyData() throws -> Data {
    BlobStore.encryptionKeyData(for: try KeychainPassphraseStore.generateKey())
}

private let tinyPNG = Data(
    base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
)!

@Suite("BlobStore — a sealed file left under another key")
struct StaleKeyBlobReuseTests {
    private static let payload = Data("stale-key-fixture".utf8) + Data([0, 1, 2, 3])

    @Test("Writing identical bytes under a new key leaves the blob readable")
    func rewriteUnderNewKeyIsReadable() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let stale = BlobStore(directory: dir, encryptionKeyData: try freshKeyData())
        let hash = try stale.write(Self.payload)
        let current = BlobStore(directory: dir, encryptionKeyData: try freshKeyData())
        #expect(current.isSealedUnderAnotherKey(hash: hash))

        #expect(try current.write(Self.payload) == hash)
        #expect(try current.read(hash: hash) == Self.payload)
        #expect(!current.isSealedUnderAnotherKey(hash: hash))
    }

    @Test("A cached thumbnail sealed under another key is regenerated")
    func staleThumbnailIsRegenerated() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let hash = try BlobStore(directory: dir, encryptionKeyData: try freshKeyData())
            .write(tinyPNG)
        let current = BlobStore(directory: dir, encryptionKeyData: try freshKeyData())
        try current.write(tinyPNG)

        #expect(try current.thumbnailData(for: hash) != nil)
    }

    @Test("A payload too large to warm drops its stale thumbnail when re-sealed")
    func largePayloadRebuildsStaleThumbnail() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        // ImageIO ignores bytes after IEND, so this stays a decodable PNG.
        let large = tinyPNG + Data(count: BlobStore.thumbnailWarmMaxBytes)
        let stale = BlobStore(directory: dir, encryptionKeyData: try freshKeyData())
        let hash = try stale.write(large)
        #expect(try stale.thumbnailData(for: hash) != nil)

        let current = BlobStore(directory: dir, encryptionKeyData: try freshKeyData())
        try current.write(large)

        #expect(try current.thumbnailData(for: hash) != nil)
    }

    @Test("A keyed store's own blob is neither flagged nor rewritten")
    func currentBlobIsKept() throws {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = BlobStore(directory: dir, encryptionKeyData: try freshKeyData())
        let hash = try store.write(Self.payload)
        let file = dir.appendingPathComponent(hash)
        let sealed = try Data(contentsOf: file)

        try store.write(Self.payload)

        #expect(try Data(contentsOf: file) == sealed)
        #expect(!store.isSealedUnderAnotherKey(hash: hash))
        #expect(!store.isSealedUnderAnotherKey(hash: String(repeating: "0", count: 64)))
        #expect(!BlobStore(directory: dir).isSealedUnderAnotherKey(hash: hash))
    }

    #if SQLITE_HAS_CODEC
        private static let content = ClipContent.binary(
            data: payload, typeIdentifier: "public.data")
        private static let imageItem = ClipItem(
            kind: .image, preview: "Image", contentHash: ClipItem.hash(of: payload, kind: .image))

        /// Seals the clip's blob file under a key the store does not have.
        private static func sealUnderLostKey(in dir: URL, data: Data = payload) throws {
            let blobs = dir.appendingPathComponent("blobs", isDirectory: true)
            let hash = try BlobStore(directory: blobs).write(data)
            try SealedEnvelope.seal(data, key: try freshKeyData())
                .write(to: blobs.appendingPathComponent(hash), options: .atomic)
        }

        @Test("A database reset that keeps blobs/ still yields preparable uploads")
        func pendingUploadSurvivesDatabaseOnlyReset() async throws {
            let dir = tempDir()
            defer { try? FileManager.default.removeItem(at: dir) }

            var old: GRDBClipboardStore? = try GRDBClipboardStore(
                directory: dir, passphrase: try KeychainPassphraseStore.generateKey())
            try await old?.insert(Self.imageItem, content: Self.content)
            old = nil
            // Before stores archived whole generations, recovery moved only the
            // database files aside and left blobs/ in the live namespace.
            for name in ["gancho.sqlite", "gancho.sqlite-wal", "gancho.sqlite-shm"] {
                try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
            }

            let store = try GRDBClipboardStore(
                directory: dir, passphrase: try KeychainPassphraseStore.generateKey())
            let item = try await store.insert(Self.imageItem, content: Self.content)

            let pending = try await store.pendingUpload(id: item.id)
            #expect(pending?.content == Self.content)
        }

        @Test("Only never-synced clips under a lost key are reported unrecoverable")
        func scanReportsOnlyLostLocalClips() async throws {
            let dir = tempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let store = try GRDBClipboardStore(
                directory: dir, passphrase: try KeychainPassphraseStore.generateKey())
            let lost = try await store.insert(Self.imageItem, content: Self.content)
            let readable = try await store.insert(
                ClipItem(
                    kind: .image, preview: "Image",
                    contentHash: ClipItem.hash(of: tinyPNG, kind: .image)),
                content: .binary(data: tinyPNG, typeIdentifier: "public.png"))
            let text = try await store.insert(
                ClipItem(
                    kind: .text, preview: "text", contentHash: ClipItem.hash(of: "t", kind: .text)),
                content: .text("t"))
            try Self.sealUnderLostKey(in: dir)

            #expect(try await store.unrecoverableLocalClipIDs() == [lost.id])
            #expect(!(try await store.unrecoverableLocalClipIDs()).contains(readable.id))
            #expect(!(try await store.unrecoverableLocalClipIDs()).contains(text.id))

            try await store.markUploaded(id: lost.id, systemFields: Data([1]))
            #expect(try await store.unrecoverableLocalClipIDs().isEmpty)
        }

        @Test("Capturing the same bytes again heals an unrecoverable clip")
        func recaptureHealsLostClip() async throws {
            let dir = tempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let store = try GRDBClipboardStore(
                directory: dir, passphrase: try KeychainPassphraseStore.generateKey())
            let lost = try await store.insert(Self.imageItem, content: Self.content)
            try Self.sealUnderLostKey(in: dir)
            #expect(try await store.unrecoverableLocalClipIDs() == [lost.id])

            try await store.importBatch([
                (
                    item: ClipItem(
                        kind: .image, preview: "Image", contentHash: Self.imageItem.contentHash),
                    content: Self.content
                )
            ])

            #expect(try await store.unrecoverableLocalClipIDs().isEmpty)
            #expect(try await store.content(for: lost.id) == Self.content)
        }

        /// The same clip as the server would send it back.
        private static func serverCopy(
            of item: ClipItem, updatedAt: Date, content: ClipContent?
        ) -> RemoteClipChange {
            RemoteClipChange(
                item: ClipItem(
                    id: item.id, createdAt: item.createdAt, updatedAt: updatedAt,
                    kind: item.kind, preview: item.preview, contentHash: item.contentHash),
                content: content, systemFields: Data([2]), boardIDs: [])
        }

        @Test("Synced clips under a lost key are counted apart from local ones")
        func scanSeparatesSyncedClips() async throws {
            let dir = tempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let store = try GRDBClipboardStore(
                directory: dir, passphrase: try KeychainPassphraseStore.generateKey())
            let lost = try await store.insert(Self.imageItem, content: Self.content)
            try await store.markUploaded(id: lost.id, systemFields: Data([1]))
            try Self.sealUnderLostKey(in: dir)

            #expect(try await store.unrecoverableSyncedClipIDs() == [lost.id])
            #expect(try await store.unrecoverableLocalClipIDs().isEmpty)
        }

        @Test("The server copy heals a dirty synced clip even when the local row wins")
        func serverCopyHealsDirtyClip() async throws {
            let dir = tempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let store = try GRDBClipboardStore(
                directory: dir, passphrase: try KeychainPassphraseStore.generateKey())
            let lost = try await store.insert(Self.imageItem, content: Self.content)
            try await store.markUploaded(id: lost.id, systemFields: Data([1]))
            try await store.markNeedsUpload(id: lost.id)
            try Self.sealUnderLostKey(in: dir)
            await #expect(throws: (any Error).self) { try await store.pendingUpload(id: lost.id) }

            let summary = try await store.applyRemoteChanges(
                clips: [
                    Self.serverCopy(
                        of: lost, updatedAt: lost.updatedAt.addingTimeInterval(-60),
                        content: Self.content)
                ],
                boards: [], clipDeletions: [], boardDeletions: [])

            #expect(summary.skippedAsStale == 1)
            #expect(try await store.unrecoverableSyncedClipIDs().isEmpty)
            #expect(try await store.pendingUpload(id: lost.id)?.content == Self.content)
        }

        @Test("Removing a synced clip locally leaves no tombstone to delete it in iCloud")
        func localOnlyDeleteLeavesNoTombstone() async throws {
            let dir = tempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let store = try GRDBClipboardStore(
                directory: dir, passphrase: try KeychainPassphraseStore.generateKey())
            let lost = try await store.insert(Self.imageItem, content: Self.content)
            try await store.markUploaded(id: lost.id, systemFields: Data([1]))

            try await store.deleteLocalOnly(id: lost.id)

            #expect(try await store.content(for: lost.id) == nil)
            #expect(try await store.pendingDeletionRecordIDs().isEmpty)
        }

        @Test("A server copy without its payload leaves the clip unreadable")
        func serverCopyWithoutPayloadDoesNotHeal() async throws {
            let dir = tempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let store = try GRDBClipboardStore(
                directory: dir, passphrase: try KeychainPassphraseStore.generateKey())
            let lost = try await store.insert(Self.imageItem, content: Self.content)
            try await store.markUploaded(id: lost.id, systemFields: Data([1]))
            try Self.sealUnderLostKey(in: dir)

            _ = try await store.applyRemoteChanges(
                clips: [
                    Self.serverCopy(
                        of: lost, updatedAt: lost.updatedAt.addingTimeInterval(60), content: nil)
                ],
                boards: [], clipDeletions: [], boardDeletions: [])

            #expect(try await store.unrecoverableSyncedClipIDs() == [lost.id])
        }

        @Test("One scan record covers never-synced and synced clips")
        func oneRecordCoversBothBuckets() async throws {
            let dir = tempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let store = try GRDBClipboardStore(
                directory: dir, passphrase: try KeychainPassphraseStore.generateKey())
            let lost = try await store.insert(Self.imageItem, content: Self.content)
            let later = try await store.insert(
                ClipItem(
                    kind: .image, preview: "Image",
                    contentHash: ClipItem.hash(of: tinyPNG, kind: .image)),
                content: .binary(data: tinyPNG, typeIdentifier: "public.png"))
            try Self.sealUnderLostKey(in: dir)
            #expect(try await store.unrecoverableLocalClipIDs() == [lost.id])

            // Opening every blob again on each count is what the record avoids.
            try Self.sealUnderLostKey(in: dir, data: tinyPNG)
            #expect(try await store.unrecoverableLocalClipIDs() == [lost.id])

            try await store.markUploaded(id: lost.id, systemFields: Data([1]))
            #expect(try await store.unrecoverableSyncedClipIDs() == [lost.id])
            #expect(try await store.unrecoverableLocalClipIDs().isEmpty)

            try FileManager.default.removeItem(
                at: dir.appendingPathComponent("blobs")
                    .appendingPathComponent(GRDBClipboardStore.keyCheckFile))
            #expect(try await store.unrecoverableLocalClipIDs() == [later.id])
        }

        @Test("After the first synced scan, only the clips it found are rechecked")
        func laterScansRecheckOnlyKnownClips() async throws {
            let dir = tempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let store = try GRDBClipboardStore(
                directory: dir, passphrase: try KeychainPassphraseStore.generateKey())
            let lost = try await store.insert(Self.imageItem, content: Self.content)
            try await store.markUploaded(id: lost.id, systemFields: Data([1]))
            try Self.sealUnderLostKey(in: dir)
            #expect(try await store.unrecoverableSyncedClipIDs() == [lost.id])

            _ = try await store.applyRemoteChanges(
                clips: [
                    Self.serverCopy(of: lost, updatedAt: lost.updatedAt, content: Self.content)
                ],
                boards: [], clipDeletions: [], boardDeletions: [])
            #expect(try await store.unrecoverableSyncedClipIDs().isEmpty)

            // No write path seals a new file under another key, so this
            // simulated one is only seen once the scan record is gone.
            try Self.sealUnderLostKey(in: dir)
            #expect(try await store.unrecoverableSyncedClipIDs().isEmpty)
            try FileManager.default.removeItem(
                at: dir.appendingPathComponent("blobs")
                    .appendingPathComponent(GRDBClipboardStore.keyCheckFile))
            #expect(try await store.unrecoverableSyncedClipIDs() == [lost.id])
        }
    #endif
}

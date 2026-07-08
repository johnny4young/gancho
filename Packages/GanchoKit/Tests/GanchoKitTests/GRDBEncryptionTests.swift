import Foundation
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

// The whole suite only makes sense when the build links SQLCipher; on a
// plaintext build the encrypted path compiles out and there is nothing to assert.
#if SQLITE_HAS_CODEC

    /// A 256-bit hex key, like `KeychainPassphraseStore` produces.
    private func testKey() throws -> String { try KeychainPassphraseStore.generateKey() }

    /// Raw bytes of every on-disk database file (main + WAL + SHM) for the store
    /// at `dir`. The needle scan must cover the WAL: a freshly written clip can
    /// live there before a checkpoint folds it into the main file.
    private func databaseBytes(in dir: URL) throws -> Data {
        var bytes = Data()
        for suffix in ["", "-wal", "-shm"] {
            let url = dir.appendingPathComponent("gancho.sqlite" + suffix)
            if let data = try? Data(contentsOf: url) { bytes.append(data) }
        }
        return bytes
    }

    private func fileBytes(in dir: URL) throws -> [Data] {
        guard FileManager.default.fileExists(atPath: dir.path) else { return [] }
        let urls = try FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles])
        return try urls.compactMap { url in
            let values = try url.resourceValues(forKeys: [.isRegularFileKey])
            return values.isRegularFile == true ? try Data(contentsOf: url) : nil
        }
    }

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("gancho-enc-\(UUID().uuidString)", isDirectory: true)
    }

    private let magicHeader = Data("SQLite format 3\u{0}".utf8)
    private let encryptedTinyPNG = Data(
        base64Encoded:
            "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
    )!
    private let pngHeader = Data([0x89, 0x50, 0x4e, 0x47])

    @Suite("GRDBClipboardStore — SQLCipher encryption at rest")
    struct GRDBEncryptionTests {
        private static let needle = "GANCHO-PLAINTEXT-NEEDLE-PAYLOAD-42"

        @Test("An encrypted store leaks no content, preview, or magic header to disk")
        func encryptedStoreRevealsNothing() async throws {
            let dir = tempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let key = try testKey()

            var store: GRDBClipboardStore? = try GRDBClipboardStore(directory: dir, passphrase: key)
            let item = ClipItem(
                kind: .text, title: Self.needle, preview: Self.needle,
                contentHash: ClipItem.hash(of: Self.needle, kind: .text))
            try await store?.insert(item, content: .text(Self.needle))
            store = nil  // release → pool closes and checkpoints the WAL

            let raw = try databaseBytes(in: dir)
            #expect(!raw.isEmpty, "the database file should exist")
            #expect(
                raw.range(of: Data(Self.needle.utf8)) == nil,
                "clip content/preview/title must not appear in cleartext on disk")
            let head = raw.prefix(16)
            #expect(
                head != magicHeader, "an encrypted database must not carry the SQLite magic header")
        }

        @Test("Encrypted stores seal binary blob payloads and read them back")
        func encryptedStoreSealsBinaryBlobs() async throws {
            let dir = tempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let key = try testKey()
            let payload = Data(Self.needle.utf8) + Data([0, 1, 2, 3])

            var store: GRDBClipboardStore? = try GRDBClipboardStore(directory: dir, passphrase: key)
            let item = ClipItem(
                kind: .image, preview: "Image",
                contentHash: ClipItem.hash(of: payload, kind: .image))
            try await store?.insert(
                item, content: .binary(data: payload, typeIdentifier: "public.data"))
            store = nil

            let blobDir = dir.appendingPathComponent("blobs", isDirectory: true)
            let rawBlob = try #require(try fileBytes(in: blobDir).first)
            #expect(
                rawBlob.prefix(BlobStore.encryptedMagic.count).elementsEqual(
                    BlobStore.encryptedMagic),
                "blob file should use the sealed blob format")
            #expect(
                rawBlob.range(of: Data(Self.needle.utf8)) == nil,
                "binary payload must not appear in cleartext on disk")

            let reopened = try GRDBClipboardStore(directory: dir, passphrase: key)
            #expect(
                try await reopened.content(for: item.id)
                    == .binary(data: payload, typeIdentifier: "public.data"))
        }

        @Test("Encrypted thumbnail cache is sealed on disk")
        func encryptedThumbnailCacheIsSealed() async throws {
            let dir = tempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let key = try testKey()

            var store: GRDBClipboardStore? = try GRDBClipboardStore(directory: dir, passphrase: key)
            let item = ClipItem(
                kind: .image, preview: "Image",
                contentHash: ClipItem.hash(of: encryptedTinyPNG, kind: .image))
            try await store?.insert(
                item, content: .binary(data: encryptedTinyPNG, typeIdentifier: "public.png"))
            let thumbnail = try #require(try await store?.thumbnailData(for: item.id))
            #expect(!thumbnail.isEmpty)
            #expect(try await store?.thumbnailURL(for: item.id) == nil)
            #expect(try await store?.thumbnailData(for: item.id) == thumbnail)
            store = nil

            let thumbnailDir = dir.appendingPathComponent("blobs/thumbnails", isDirectory: true)
            let rawThumbnail = try #require(try fileBytes(in: thumbnailDir).first)
            #expect(
                rawThumbnail.prefix(BlobStore.encryptedMagic.count).elementsEqual(
                    BlobStore.encryptedMagic),
                "thumbnail cache should use the sealed blob format")
            #expect(
                rawThumbnail.range(of: pngHeader) == nil,
                "cached thumbnails must not remain as plaintext PNG files")
        }

        @Test("The right key reads the clips back; a wrong key cannot open the store")
        func keyGatesAccess() async throws {
            let dir = tempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let key = try testKey()

            var store: GRDBClipboardStore? = try GRDBClipboardStore(directory: dir, passphrase: key)
            let item = ClipItem(
                kind: .text, preview: "secret",
                contentHash: ClipItem.hash(of: Self.needle, kind: .text))
            try await store?.insert(item, content: .text(Self.needle))
            store = nil

            // Correct key → content round-trips.
            let reopened = try GRDBClipboardStore(directory: dir, passphrase: key)
            #expect(try await reopened.content(for: item.id) == .text(Self.needle))

            // Wrong key → the store cannot be opened at all.
            #expect(throws: (any Error).self) {
                _ = try GRDBClipboardStore(directory: dir, passphrase: try testKey())
            }
        }

        @Test("A fresh key recovers a store keyed by an unreachable key (archived, not deleted)")
        func recoversStoreKeyedByUnreachableKey() async throws {
            let dir = tempDir()
            defer { try? FileManager.default.removeItem(at: dir) }

            // A store encrypted by a key this build can no longer reach — the
            // real-world case is the direct-download build meeting a store keyed
            // by a synchronizable (iCloud Keychain) key it can't read.
            var store: GRDBClipboardStore? = try GRDBClipboardStore(
                directory: dir, passphrase: try testKey())
            try await store?.insert(
                ClipItem(
                    kind: .text, preview: "stranded",
                    contentHash: ClipItem.hash(of: Self.needle, kind: .text)),
                content: .text(Self.needle))
            store = nil  // release so the pool closes before the reopen

            // A DIFFERENT, freshly generated key can't decrypt it. With
            // keyIsFresh = true, the unreadable file is archived aside and a
            // fresh store takes its place.
            let recovered = try GRDBClipboardStore.openEncrypted(
                directory: dir, key: try testKey(), keyIsFresh: true)
            #expect(try await recovered.count() == 0, "the recovered store starts empty")

            let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            #expect(
                names.contains { $0.hasPrefix("gancho.sqlite.unreadable-") },
                "the unreadable database is moved aside, never deleted")
        }

        @Test("Unreadable archive suffixes are collision-resistant within one second")
        func unreadableArchiveSuffixIsCollisionResistant() throws {
            let now = Date(timeIntervalSince1970: 1_785_000_000)
            let firstID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
            let secondID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))

            let first = GRDBClipboardStore.unreadableStoreArchiveSuffix(now: now, uuid: firstID)
            let second = GRDBClipboardStore.unreadableStoreArchiveSuffix(now: now, uuid: secondID)

            #expect(first == "1785000000-00000000-0000-0000-0000-000000000001")
            #expect(second == "1785000000-00000000-0000-0000-0000-000000000002")
            #expect(first != second)
        }

        @Test("A non-fresh key never resets — a reachable-key mismatch surfaces")
        func nonFreshKeyNeverResets() async throws {
            let dir = tempDir()
            defer { try? FileManager.default.removeItem(at: dir) }

            var store: GRDBClipboardStore? = try GRDBClipboardStore(
                directory: dir, passphrase: try testKey())
            try await store?.insert(
                ClipItem(kind: .text, preview: "x", contentHash: "h"), content: .text("x"))
            store = nil

            // keyIsFresh = false means the key was read from the keychain, so a
            // failure to open is real corruption (or a reachable-key mismatch),
            // never silently reset.
            #expect(throws: (any Error).self) {
                _ = try GRDBClipboardStore.openEncrypted(
                    directory: dir, key: try testKey(), keyIsFresh: false)
            }
            let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            #expect(
                !names.contains { $0.hasPrefix("gancho.sqlite.unreadable-") },
                "a non-fresh failure must leave the store untouched")
        }

        @Test("A pre-encryption plaintext store migrates in place without losing clips")
        func migratesPlaintextStore() async throws {
            let dir = tempDir()
            defer { try? FileManager.default.removeItem(at: dir) }

            // 1. Seed a plaintext store (passphrase nil ⇒ no encryption).
            var plaintext: GRDBClipboardStore? = try GRDBClipboardStore(
                directory: dir, passphrase: nil)
            let item = ClipItem(
                kind: .text, preview: "carried over",
                contentHash: ClipItem.hash(of: Self.needle, kind: .text))
            try await plaintext?.insert(item, content: .text(Self.needle))
            plaintext = nil

            // Sanity: on disk it really is plaintext.
            let before = try databaseBytes(in: dir)
            #expect(before.prefix(16) == magicHeader, "seed store should be plaintext")
            #expect(
                before.range(of: Data(Self.needle.utf8)) != nil, "seed content should be cleartext")

            // 2. Reopen WITH a key ⇒ in-place re-encryption runs.
            let key = try testKey()
            let encrypted = try GRDBClipboardStore(directory: dir, passphrase: key)

            // Clip survived.
            #expect(try await encrypted.content(for: item.id) == .text(Self.needle))
            #expect(try await encrypted.count() == 1)

            // And the file is now encrypted.
            let after = try databaseBytes(in: dir)
            #expect(after.prefix(16) != magicHeader, "store should be encrypted after migration")
            #expect(
                after.range(of: Data(Self.needle.utf8)) == nil,
                "migrated content must no longer be cleartext on disk")
        }

        @Test("Pre-encryption blob payloads and thumbnails migrate in place")
        func migratesPlaintextBlobsAndThumbnails() async throws {
            let dir = tempDir()
            defer { try? FileManager.default.removeItem(at: dir) }

            var plaintext: GRDBClipboardStore? = try GRDBClipboardStore(
                directory: dir, passphrase: nil)
            let item = ClipItem(
                kind: .image, preview: "Image",
                contentHash: ClipItem.hash(of: encryptedTinyPNG, kind: .image))
            try await plaintext?.insert(
                item, content: .binary(data: encryptedTinyPNG, typeIdentifier: "public.png"))
            let plaintextThumbnailURL = try #require(
                try await plaintext?.thumbnailURL(for: item.id))
            let plaintextThumbnail = try Data(contentsOf: plaintextThumbnailURL)
            plaintext = nil

            let blobDir = dir.appendingPathComponent("blobs", isDirectory: true)
            let thumbnailDir = dir.appendingPathComponent("blobs/thumbnails", isDirectory: true)
            let beforeBlob = try #require(try fileBytes(in: blobDir).first)
            let beforeThumbnail = try #require(try fileBytes(in: thumbnailDir).first)
            #expect(beforeBlob == encryptedTinyPNG, "seed blob should be plaintext")
            #expect(
                beforeThumbnail.range(of: pngHeader) != nil,
                "seed thumbnail should be a plaintext PNG")

            let key = try testKey()
            let encrypted = try GRDBClipboardStore(directory: dir, passphrase: key)

            #expect(
                try await encrypted.content(for: item.id)
                    == .binary(data: encryptedTinyPNG, typeIdentifier: "public.png"))
            #expect(try await encrypted.thumbnailData(for: item.id) == plaintextThumbnail)

            let afterBlob = try #require(try fileBytes(in: blobDir).first)
            let afterThumbnail = try #require(try fileBytes(in: thumbnailDir).first)
            #expect(
                afterBlob.prefix(BlobStore.encryptedMagic.count).elementsEqual(
                    BlobStore.encryptedMagic),
                "migrated blob should be sealed")
            #expect(
                afterThumbnail.prefix(BlobStore.encryptedMagic.count).elementsEqual(
                    BlobStore.encryptedMagic),
                "migrated thumbnail should be sealed")
            #expect(
                afterBlob.range(of: encryptedTinyPNG) == nil,
                "migrated binary payload must not remain cleartext")
            #expect(
                afterThumbnail.range(of: pngHeader) == nil,
                "migrated thumbnail must not remain a plaintext PNG")
        }
    }

#endif

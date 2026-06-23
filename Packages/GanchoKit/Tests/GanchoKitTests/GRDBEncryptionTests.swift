import Foundation
import Testing

@testable import GanchoKit

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

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("gancho-enc-\(UUID().uuidString)", isDirectory: true)
    }

    private let magicHeader = Data("SQLite format 3\u{0}".utf8)

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
    }

#endif

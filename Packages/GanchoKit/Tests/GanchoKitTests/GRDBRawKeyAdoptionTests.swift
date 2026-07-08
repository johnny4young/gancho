import Foundation
import Testing

@testable import GanchoKit

// Raw-key adoption only exists on SQLCipher builds; on a plaintext build the
// whole path compiles out and there is nothing to assert.
#if SQLITE_HAS_CODEC

    /// A 256-bit hex key, like `KeychainPassphraseStore` produces.
    private func testKey() throws -> String { try KeychainPassphraseStore.generateKey() }

    private func tempDir() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("gancho-rawkey-\(UUID().uuidString)", isDirectory: true)
    }

    private func dbPath(_ dir: URL) -> String {
        dir.appendingPathComponent("gancho.sqlite").path
    }

    /// True when a single keyed, read-only page read succeeds with `key`
    /// (either the bare hex — the legacy KDF form — or the x'…' raw literal).
    /// Uses the engine's own probe so the test asserts the exact primitive the
    /// adoption path trusts.
    private func opens(_ dir: URL, key: String) -> Bool {
        GRDBClipboardStore.opensWithKey(path: dbPath(dir), key: key)
    }

    /// Builds a store keyed the LEGACY way — PBKDF2 over the bare hex string —
    /// via the UNCHANGED production `init(directory:passphrase:)`, which is
    /// exactly what every existing install has on disk. (The adoption path is
    /// unwired, so the production init still keys through the KDF; if that init
    /// is ever flipped to raw-first, this fixture must be rebuilt by hand like
    /// the dossier's `makeDerivedKeyStore`.)
    private func makeDerivedKeyStore(
        at dir: URL, key: String, items: [(ClipItem, ClipContent?)]
    ) async throws {
        var store: GRDBClipboardStore? = try GRDBClipboardStore(directory: dir, passphrase: key)
        for (item, content) in items {
            try await store?.insert(item, content: content)
        }
        store = nil  // release → pool closes and checkpoints
    }

    @Suite("GRDBClipboardStore — SQLCipher raw-key adoption (unwired path)")
    struct GRDBRawKeyAdoptionTests {
        private static let needle = "GANCHO-RAWKEY-NEEDLE-PAYLOAD-7"
        private static let blobPayload = Data("GANCHO-RAWKEY-BLOB".utf8) + Data([0, 1, 2, 3])

        private static func fixtureItems() -> [(ClipItem, ClipContent?)] {
            var items: [(ClipItem, ClipContent?)] = (0..<10).map { index in
                let text = "\(needle)-\(index)"
                return (
                    ClipItem(
                        kind: .text, preview: String(text.prefix(120)),
                        contentHash: ClipItem.hash(of: text, kind: .text)),
                    .text(text)
                )
            }
            items.append(
                (
                    ClipItem(
                        kind: .image, preview: "Image",
                        contentHash: ClipItem.hash(of: blobPayload, kind: .image)),
                    .binary(data: blobPayload, typeIdentifier: "public.data")
                ))
            return items
        }

        @Test("rawKeyLiteral accepts exactly 64 hex digits and nothing else")
        func rawKeyLiteralValidation() throws {
            let key = try testKey()
            #expect(GRDBClipboardStore.rawKeyLiteral(for: key) == "x'\(key)'")
            // Whitespace-tolerant, matching BlobStore.encryptionKeyData(for:).
            #expect(GRDBClipboardStore.rawKeyLiteral(for: key + "\n") == "x'\(key)'")
            // Anything not exactly 64 hex digits keeps the PBKDF2 behavior.
            #expect(GRDBClipboardStore.rawKeyLiteral(for: "") == nil)
            #expect(GRDBClipboardStore.rawKeyLiteral(for: "not a hex key") == nil)
            #expect(GRDBClipboardStore.rawKeyLiteral(for: String(key.dropLast())) == nil)
            #expect(GRDBClipboardStore.rawKeyLiteral(for: key + "ab") == nil)
            #expect(
                GRDBClipboardStore.rawKeyLiteral(for: String(key.dropLast()) + "g") == nil)
        }

        @Test("A legacy derived-key store is rekeyed on open with zero data loss")
        func derivedStoreIsRekeyedWithoutDataLoss() async throws {
            let dir = tempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let key = try testKey()
            let items = Self.fixtureItems()
            try await makeDerivedKeyStore(at: dir, key: key, items: items)
            #expect(opens(dir, key: key), "fixture must start in the legacy derived form")
            #expect(!opens(dir, key: "x'\(key)'"), "fixture must not already be raw-keyed")

            // First open with the adopting path: migrates, then reads every row.
            var migrated: GRDBClipboardStore? = try GRDBClipboardStore.encryptedRawKeyAdopting(
                directory: dir, passphrase: key)
            #expect(try await migrated?.count() == items.count)
            for (item, content) in items {
                #expect(try await migrated?.content(for: item.id) == content)
            }
            migrated = nil

            // The rekey really happened: raw opens, the derived form no longer does.
            #expect(opens(dir, key: "x'\(key)'"), "store should now open with the raw key")
            #expect(!opens(dir, key: key), "the derived form must no longer open the store")
        }

        @Test("After adoption the raw form opens directly (no fallback machinery)")
        func secondOpenIsDirectRawOpen() async throws {
            let dir = tempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let key = try testKey()
            let items = Self.fixtureItems()
            try await makeDerivedKeyStore(at: dir, key: key, items: items)

            var migrated: GRDBClipboardStore? = try GRDBClipboardStore.encryptedRawKeyAdopting(
                directory: dir, passphrase: key)
            #expect(try await migrated?.count() == items.count)
            migrated = nil

            // Direct proof: the plain, unchanged init — which has NO probe or
            // fallback — opens the store when handed the raw literal as its
            // passphrase. (Metadata reads only: the blob key legitimately
            // differs for this literal, which is exactly why the adopting API
            // must derive blob keys from the plain hex — asserted below.)
            var direct: GRDBClipboardStore? = try GRDBClipboardStore(
                directory: dir, passphrase: "x'\(key)'")
            #expect(try await direct?.count() == items.count)
            direct = nil

            // And the adopting API's steady state: raw probe succeeds, no
            // migration, every row — blob included — still reads back.
            let reopened = try GRDBClipboardStore.encryptedRawKeyAdopting(
                directory: dir, passphrase: key)
            #expect(try await reopened.count() == items.count)
            for (item, content) in items {
                #expect(try await reopened.content(for: item.id) == content)
            }
        }

        @Test("A wrong key fails closed and never rekeys the store")
        func wrongKeyFailsClosedWithoutRekey() async throws {
            let dir = tempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let key = try testKey()
            let items = Self.fixtureItems()
            try await makeDerivedKeyStore(at: dir, key: key, items: items)

            // Wrong 64-hex key: raw probe fails, derived fallback fails, the
            // open throws — and must not have touched the file.
            let wrongKey = try testKey()
            #expect(throws: (any Error).self) {
                _ = try GRDBClipboardStore.encryptedRawKeyAdopting(
                    directory: dir, passphrase: wrongKey)
            }
            #expect(opens(dir, key: key), "a failed wrong-key open must leave the store as-was")
            #expect(!opens(dir, key: "x'\(wrongKey)'"), "the wrong key must not have rekeyed")

            // The right key still opens (and migrates) with everything intact.
            let store = try GRDBClipboardStore.encryptedRawKeyAdopting(
                directory: dir, passphrase: key)
            #expect(try await store.count() == items.count)
        }

        @Test("A fresh key recovery also applies to raw-key adoption")
        func freshKeyRecoveryAppliesToRawKeyAdoption() async throws {
            let dir = tempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let key = try testKey()
            try await makeDerivedKeyStore(at: dir, key: key, items: Self.fixtureItems())

            let recovered = try GRDBClipboardStore.openEncryptedRawKeyAdopting(
                directory: dir, key: try testKey(), keyIsFresh: true)
            #expect(try await recovered.count() == 0, "the recovered store starts empty")

            let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
            #expect(
                names.contains { $0.hasPrefix("gancho.sqlite.unreadable-") },
                "raw-key adoption must archive the unreachable store before starting fresh")
        }

        @Test("A fresh directory creates a raw-keyed store from the start")
        func freshStoreIsRawKeyed() async throws {
            let dir = tempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let key = try testKey()

            var store: GRDBClipboardStore? = try GRDBClipboardStore.encryptedRawKeyAdopting(
                directory: dir, passphrase: key)
            let item = ClipItem(
                kind: .text, preview: "fresh",
                contentHash: ClipItem.hash(of: Self.needle, kind: .text))
            try await store?.insert(item, content: .text(Self.needle))
            #expect(try await store?.content(for: item.id) == .text(Self.needle))
            store = nil  // release → pool closes and checkpoints

            #expect(opens(dir, key: "x'\(key)'"), "fresh store should open with the raw key")
            #expect(!opens(dir, key: key), "the legacy derived form must NOT open a raw store")
        }

        @Test("Binary blobs round-trip across the migration (blob key is form-independent)")
        func blobRoundTripSurvivesMigration() async throws {
            let dir = tempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let key = try testKey()
            let item = ClipItem(
                kind: .image, preview: "Image",
                contentHash: ClipItem.hash(of: Self.blobPayload, kind: .image))
            let content = ClipContent.binary(
                data: Self.blobPayload, typeIdentifier: "public.data")
            try await makeDerivedKeyStore(at: dir, key: key, items: [(item, content)])

            // Across the derived → raw migration…
            var migrated: GRDBClipboardStore? = try GRDBClipboardStore.encryptedRawKeyAdopting(
                directory: dir, passphrase: key)
            #expect(try await migrated?.content(for: item.id) == content)
            migrated = nil

            // …and again on the steady-state raw open: the blob key derives
            // from the plain hex both times, untouched by the SQLCipher form.
            let reopened = try GRDBClipboardStore.encryptedRawKeyAdopting(
                directory: dir, passphrase: key)
            #expect(try await reopened.content(for: item.id) == content)
        }

        @Test("Extensions can open a legacy store without performing the migration")
        func migrationCanBeDisallowed() async throws {
            let dir = tempDir()
            defer { try? FileManager.default.removeItem(at: dir) }
            let key = try testKey()
            let items = Self.fixtureItems()
            try await makeDerivedKeyStore(at: dir, key: key, items: items)

            var noMigration: GRDBClipboardStore? = try GRDBClipboardStore.encryptedRawKeyAdopting(
                directory: dir, passphrase: key, allowingRawKeyMigration: false)
            #expect(try await noMigration?.count() == items.count)
            noMigration = nil

            #expect(opens(dir, key: key), "a no-migration open must leave the derived key")
            #expect(!opens(dir, key: "x'\(key)'"))
        }

        @Test("A pre-encryption plaintext store converges to the raw key in one open")
        func plaintextStoreConvergesToRawKey() async throws {
            let dir = tempDir()
            defer { try? FileManager.default.removeItem(at: dir) }

            var plaintext: GRDBClipboardStore? = try GRDBClipboardStore(
                directory: dir, passphrase: nil)
            let item = ClipItem(
                kind: .text, preview: "carried over",
                contentHash: ClipItem.hash(of: Self.needle, kind: .text))
            try await plaintext?.insert(item, content: .text(Self.needle))
            plaintext = nil

            // The unchanged plaintext migration encrypts to the derived form;
            // the keying decision then rekeys derived → raw in the same open.
            let key = try testKey()
            var encrypted: GRDBClipboardStore? = try GRDBClipboardStore.encryptedRawKeyAdopting(
                directory: dir, passphrase: key)
            #expect(try await encrypted?.content(for: item.id) == .text(Self.needle))
            encrypted = nil

            #expect(opens(dir, key: "x'\(key)'"), "plaintext should converge on the raw key")
            #expect(!opens(dir, key: key), "no derived-key state should remain after the open")
        }
    }

#endif

import Foundation
import GRDB

// SQLCipher raw-key adoption — an UNWIRED, parallel open path.
//
// Production callers still open through `init(directory:passphrase:)` /
// `encrypted(directory:keychainAccessGroup:)`; nothing in the apps, the
// extensions, or the CLI calls into this file unless the environment gate is
// enabled. Roll it out only after derived-key open, raw-key probe, in-place
// rekey, relaunch, extension concurrency, rollback, and recovery pass on real
// devices; keep the raw-first open and the migration release separable.

#if SQLITE_HAS_CODEC
    extension GRDBClipboardStore {
        /// Opens the production store exactly like ``init(directory:passphrase:)``,
        /// but keys SQLCipher with the raw-key form of the 256-bit hex passphrase —
        /// skipping the ~256k-iteration PBKDF2 that SQLCipher otherwise runs per
        /// pool connection. The key is already 32 random bytes
        /// (``KeychainPassphraseStore``), so the KDF adds latency, not security.
        ///
        /// Existing databases are encrypted under the DERIVED key (KDF over the
        /// bare hex string), so this open probes the raw form first (one cheap
        /// keyed page read, no KDF); when the probe fails and
        /// `allowingRawKeyMigration` is true, it reopens with the derived key,
        /// checkpoints the WAL, re-keys the file in place to the raw form
        /// (`sqlite3_rekey` on the same inode — sibling processes are serialized,
        /// never stranded), checkpoints again, and verifies the raw key now opens
        /// before trusting it. The file's own keying is the ground truth: there is
        /// deliberately no persisted "migrated" marker.
        ///
        /// Safety properties:
        /// - A wrong key fails BOTH the raw probe and the derived open, so the
        ///   pool open below throws and the file is never re-keyed — the same
        ///   fail-closed behavior as ``init(directory:passphrase:)``.
        /// - An interrupted or contended migration (busy sibling reader, iOS
        ///   suspension) is abandoned without error: this launch opens with the
        ///   derived key and the migration retries on a later open.
        /// - The blob/thumbnail key still derives from the PLAIN hex passphrase —
        ///   never the `x'…'` literal — so sealed blobs are unaffected by which
        ///   SQLCipher key form opened the database.
        ///
        /// - Parameter allowingRawKeyMigration: pass `false` from time- and
        ///   memory-budgeted extension processes (keyboard, widgets, share): they
        ///   open raw when the database is already migrated and derived otherwise,
        ///   leaving the one-time rekey to the main app's next launch.
        public static func encryptedRawKeyAdopting(
            directory: URL, passphrase: String, allowingRawKeyMigration: Bool = true
        ) throws -> GRDBClipboardStore {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            let dbPath = directory.appendingPathComponent("gancho.sqlite").path

            var configuration = Configuration()
            #if os(iOS)
                // Mirror init(directory:passphrase:): release SQLite locks across
                // suspension instead of dying with 0xDEAD10CC in App Group
                // containers. No-op on macOS.
                configuration.observesSuspensionNotifications = true
            #endif
            // Ordering matters: a pre-encryption plaintext store is converted
            // first (to the derived form, unchanged code), then the keying
            // decision below immediately migrates it derived → raw.
            try encryptPlaintextStoreIfNeeded(at: dbPath, passphrase: passphrase)
            let sqlcipherKey = resolvedSQLCipherKey(
                at: dbPath, passphrase: passphrase,
                allowingRawKeyMigration: allowingRawKeyMigration)
            configuration.prepareDatabase { db in
                try db.usePassphrase(sqlcipherKey)
            }
            let pool = try DatabasePool(path: dbPath, configuration: configuration)
            let blobStore = BlobStore(
                directory: directory.appendingPathComponent("blobs"),
                // The blob key derives from the PLAIN hex string — never the
                // x'…' literal — or every sealed blob/thumbnail is lost.
                encryptionKeyData: BlobStore.encryptionKeyData(for: passphrase))
            try blobStore.encryptPlaintextFilesIfNeeded()
            let store = GRDBClipboardStore(writer: pool, blobs: blobStore)
            try store.migrate()
            return store
        }

        /// The SQLCipher raw-key BLOB literal (`x'<64 hex>'`) for a 256-bit hex
        /// passphrase, or nil when the passphrase is not exactly 64 hex digits
        /// (arbitrary passphrases keep the PBKDF2 behavior).
        ///
        /// SQLCipher treats key text in exactly this form — passed through
        /// `sqlite3_key`/`sqlite3_rekey`, which is what `usePassphrase` and
        /// `changePassphrase` call — as raw key material and skips the KDF.
        /// Any other text (including the bare 64-hex string, and including raw
        /// bytes via the `usePassphrase(Data)` overload) is KDF-derived.
        static func rawKeyLiteral(for passphrase: String) -> String? {
            let trimmed = passphrase.trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.count == 64, trimmed.allSatisfy(\.isHexDigit) else { return nil }
            return "x'\(trimmed)'"
        }

        /// Decides which SQLCipher key form actually opens the database at
        /// `path`, migrating a legacy KDF-derived database to the raw key in
        /// place when allowed. Total (never throws): a truly wrong key keeps
        /// today's fail-closed behavior at the pool open.
        static func resolvedSQLCipherKey(
            at path: String, passphrase: String, allowingRawKeyMigration: Bool
        ) -> String {
            guard let rawKey = rawKeyLiteral(for: passphrase) else { return passphrase }
            // Fresh install: no file yet — the pool creates it raw-keyed.
            guard FileManager.default.fileExists(atPath: path) else { return rawKey }
            // Steady state: one cheap keyed read (no KDF) proves the raw key.
            if opensWithKey(path: path, key: rawKey) { return rawKey }
            guard allowingRawKeyMigration else { return passphrase }
            if rekeyToRawKey(at: path, passphrase: passphrase, rawKey: rawKey) {
                return rawKey
            }
            // Raced a sibling process that migrated between our probe and our
            // derived open? One re-probe settles it.
            if opensWithKey(path: path, key: rawKey) { return rawKey }
            // Not migrated this launch (busy sibling, suspension, wrong key):
            // open with the legacy derived key; retry next open.
            return passphrase
        }

        /// One keyed, read-only page read. False means "not this key" OR any
        /// environmental failure — callers only ever treat true as proof.
        /// (A wrong or wrong-form key surfaces as SQLITE_NOTADB on the first
        /// page read; the keying call itself performs no I/O.)
        static func opensWithKey(path: String, key: String) -> Bool {
            var configuration = Configuration()
            configuration.readonly = true
            configuration.prepareDatabase { db in
                try db.usePassphrase(key)
            }
            guard let queue = try? DatabaseQueue(path: path, configuration: configuration)
            else { return false }
            defer { try? queue.close() }
            // COUNT(*) yields a row even for an empty schema, so a right key
            // can never be misread as wrong; the read still touches the first
            // page, which is where a wrong key fails.
            let probe = try? queue.read { db in
                try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM sqlite_master")
            }
            return probe != nil
        }

        /// One-time, in-place migration: KDF-derived key → raw key, on the SAME
        /// inode (sibling processes with open pools are serialized by SQLite's
        /// locking, never stranded on an unlinked file — the reason this is
        /// `sqlite3_rekey` and NOT a `sqlcipher_export` sibling-and-swap).
        ///
        /// Fail-safe by construction: the database is only re-keyed after a
        /// successful open with the legacy derived key, and `sqlite3_rekey` is
        /// journal-protected — an interruption (busy reader, iOS suspension)
        /// rolls back and the store keeps opening with the derived key until a
        /// later launch completes the migration.
        private static func rekeyToRawKey(
            at path: String, passphrase: String, rawKey: String
        ) -> Bool {
            var configuration = Configuration()
            configuration.busyMode = .timeout(2)
            #if os(iOS)
                // Mirror the pool: release locks instead of dying with
                // 0xDEAD10CC if iOS suspends the app mid-rekey.
                configuration.observesSuspensionNotifications = true
            #endif
            configuration.prepareDatabase { db in
                try db.usePassphrase(passphrase)  // the legacy derived form
            }
            guard let queue = try? DatabaseQueue(path: path, configuration: configuration)
            else { return false }  // wrong key or busy — leave the file alone
            defer { try? queue.close() }
            let rekeyed: Bool =
                (try? queue.writeWithoutTransaction { db -> Bool in
                    // Fold every derived-key WAL frame into the main file first,
                    // so no frame encrypted with the old key survives the switch…
                    try db.checkpoint(.truncate)
                    try db.changePassphrase(rawKey)  // sqlite3_rekey: in place
                    // …and fold the re-keyed pages, leaving an empty WAL.
                    try db.checkpoint(.truncate)
                    return true
                }) ?? false
            guard rekeyed else { return false }
            // Paranoia over trust: only report success if the raw key now
            // actually opens the file.
            return opensWithKey(path: path, key: rawKey)
        }
    }
#endif

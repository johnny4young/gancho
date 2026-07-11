import Foundation
import GRDB

// This class owns the schema, query surface, and migration boundary. Split
// storage responsibilities in a dedicated database refactor, not in lint setup.
// swiftlint:disable type_body_length

/// SQLite-backed source of truth for clip history (GRDB).
///
/// Layout decisions (see docs/ARCHITECTURE.md):
/// - Metadata + full TEXT content live in the `clip` table; binary payloads
///   live on disk via `BlobStore` (the row keeps a content-hash reference).
///   The encrypted production store also encrypts those blob files and cached
///   thumbnails. List queries page metadata only — blobs never ride along.
/// - Schema changes go through `DatabaseMigrator`, versioned from v1.
///   NEVER edit a registered migration; append a new one.
/// - The store never imports CloudKit: sync goes through the `SyncEngine`
///   boundary, fed by the same records.
public final class GRDBClipboardStore: ClipboardStore {
    // swiftlint:enable type_body_length
    /// Internal (not private) so same-module engines (retention, sync feed)
    /// and the test harness can run statements without widening the API.
    let writer: any DatabaseWriter
    private let blobs: BlobStore

    /// Maintenance-only blob access for same-module engines (orphan sweeps).
    var blobsForMaintenance: BlobStore { blobs }

    /// Production store at a directory (database + blobs side by side).
    ///
    /// - Parameter passphrase: when non-nil and the build links SQLCipher, the
    ///   whole database — including the FTS5 index — is encrypted at rest with
    ///   this key (see ``KeychainPassphraseStore``). A pre-encryption plaintext
    ///   database is transparently re-encrypted in place before the pool opens.
    ///   When nil (or on a non-SQLCipher build) the store is plaintext — the
    ///   path used by tests and the perf harness.
    public convenience init(directory: URL, passphrase: String? = nil) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let dbPath = directory.appendingPathComponent("gancho.sqlite").path

        var configuration = Configuration()
        #if os(iOS)
            // iOS terminates an app with 0xDEAD10CC if it holds a SQLite lock
            // while suspended and the database lives in a shared App Group
            // container. GRDB releases locks across suspension when this flag is
            // set AND the app posts `DatabaseSuspension` notifications on the
            // background/foreground boundary. No-op on macOS (nothing suspends).
            configuration.observesSuspensionNotifications = true
        #endif
        // Interactive reads fan out — list page + thumbnail decrypts + search
        // + the sync feed — and GRDB's default reader cap (5) lets one slow
        // reader head-of-line-block the rest. 8 matches that fan-out without
        // over-provisioning (each reader is a connection + page cache). Heavy
        // scans stay off the interactive budget by their own bounds: regex
        // sweeps run under the A-2 ceiling and exports stream through a
        // single read (`.audit/14` B-10).
        configuration.maximumReaderCount = 8
        let blobEncryptionKeyData: Data?
        #if SQLITE_HAS_CODEC
            if let passphrase {
                try Self.encryptPlaintextStoreIfNeeded(at: dbPath, passphrase: passphrase)
                configuration.prepareDatabase { db in
                    try db.usePassphrase(passphrase)
                }
                blobEncryptionKeyData = BlobStore.encryptionKeyData(for: passphrase)
            } else {
                blobEncryptionKeyData = nil
            }
        #else
            blobEncryptionKeyData = nil
        #endif

        let pool = try DatabasePool(path: dbPath, configuration: configuration)
        let blobStore = BlobStore(
            directory: directory.appendingPathComponent("blobs"),
            encryptionKeyData: blobEncryptionKeyData)
        try blobStore.encryptPlaintextFilesIfNeeded()
        self.init(
            writer: pool,
            blobs: blobStore)
        try migrator.migrate(pool)
        // NOTE: the cosmetic legacy-preview backfill is deliberately NOT run
        // here — it scanned image rows inside a write transaction on every
        // open, taxing cold launch in the app and every extension. Apps call
        // `backfillLegacyPreviews()` after first render instead.
    }

    /// Opens the production store encrypted with the Keychain-managed key.
    ///
    /// The path the apps and the CLI use: it loads (or, on first launch,
    /// generates) the random 256-bit key from ``KeychainPassphraseStore`` and
    /// hands it to ``init(directory:passphrase:)``, which encrypts the database
    /// and migrates any pre-encryption plaintext store. Distinct from the
    /// plaintext `init`s that tests and the perf harness use.
    ///
    /// - Parameter keychainAccessGroup: shared keychain group for iOS
    ///   database-reading extensions; `nil` for the macOS app, the CLI, and the
    ///   iOS main app (which use their default keychain).
    ///
    /// - Note: Setting `GANCHO_RAWKEY_ADOPT=1` in the launch environment routes
    ///   this open through the raw-key variant in RawKeyAdoption.swift
    ///   (`encryptedRawKeyAdopting(directory:passphrase:allowingRawKeyMigration:)`),
    ///   which skips SQLCipher's per-connection PBKDF2 for our random 256-bit
    ///   keys and migrates the file to the raw key form in place. OFF by
    ///   default; flip it only per the on-device rollout checklist in
    ///   `.audit/06-sqlcipher-rawkey-rekey.md` §5.
    public static func encrypted(
        directory: URL,
        keychainAccessGroup: String? = nil
    ) throws -> GRDBClipboardStore {
        let resolved = try KeychainPassphraseStore(accessGroup: keychainAccessGroup)
            .loadOrCreateKeyReportingFreshness()
        #if SQLITE_HAS_CODEC
            if rawKeyAdoptionEnabled() {
                return try openEncryptedRawKeyAdopting(
                    directory: directory, key: resolved.key, keyIsFresh: resolved.isFresh)
            }
        #endif
        return try openEncrypted(
            directory: directory, key: resolved.key, keyIsFresh: resolved.isFresh)
    }

    /// Opens the encrypted store, recovering from a store that was keyed by an
    /// unreachable key. This happens when a build can't reach the key that
    /// encrypted an existing database — e.g. the direct-download build, whose
    /// slim entitlements can't read a synchronizable (iCloud Keychain) key that
    /// a differently-signed build created. A brand-new key can never decrypt
    /// such a file, so — and ONLY when the key is freshly generated AND the open
    /// fails specifically because the file won't decrypt — the unreadable
    /// database is moved aside (never deleted: an entitled build could still
    /// recover it) and a fresh one is created. A reachable-key corruption or a
    /// transient error is re-thrown untouched, never silently reset.
    static func openEncrypted(
        directory: URL, key: String, keyIsFresh: Bool
    ) throws -> GRDBClipboardStore {
        do {
            return try GRDBClipboardStore(directory: directory, passphrase: key)
        } catch {
            guard keyIsFresh, isDecryptionFailure(error) else { throw error }
            try archiveUnreadableStore(in: directory)
            return try GRDBClipboardStore(directory: directory, passphrase: key)
        }
    }

    /// Whether an open failure is SQLCipher rejecting the key (the first read of
    /// a wrong-keyed database returns `SQLITE_NOTADB`), as opposed to a transient
    /// I/O or busy error that a reset would wrongly destroy data over.
    static func isDecryptionFailure(_ error: Error) -> Bool {
        guard let dbError = error as? DatabaseError else { return false }
        return dbError.resultCode == .SQLITE_NOTADB
    }

    /// Moves an unreadable encrypted database (and its WAL/SHM siblings) aside to
    /// a timestamped, collision-resistant `.unreadable-*` name so a fresh store
    /// can take its place.
    /// Content-addressed blobs are left in place — the fresh database won't
    /// reference them, and an orphan sweep reclaims them later.
    static func archiveUnreadableStore(in directory: URL) throws {
        let fileManager = FileManager.default
        let suffix = unreadableStoreArchiveSuffix()
        for name in ["gancho.sqlite", "gancho.sqlite-wal", "gancho.sqlite-shm"] {
            let source = directory.appendingPathComponent(name)
            guard fileManager.fileExists(atPath: source.path) else { continue }
            let destination = directory.appendingPathComponent("\(name).unreadable-\(suffix)")
            try fileManager.moveItem(at: source, to: destination)
        }
    }

    static func unreadableStoreArchiveSuffix(
        now: Date = Date(), uuid: UUID = UUID()
    ) -> String {
        "\(Int(now.timeIntervalSince1970))-\(uuid.uuidString)"
    }

    #if SQLITE_HAS_CODEC
        static func openEncryptedRawKeyAdopting(
            directory: URL, key: String, keyIsFresh: Bool
        ) throws -> GRDBClipboardStore {
            do {
                return try encryptedRawKeyAdopting(directory: directory, passphrase: key)
            } catch {
                guard keyIsFresh, isDecryptionFailure(error) else { throw error }
                try archiveUnreadableStore(in: directory)
                return try encryptedRawKeyAdopting(directory: directory, passphrase: key)
            }
        }
    #endif

    /// True when the launch environment opts this process into the raw-key
    /// open path (`GANCHO_RAWKEY_ADOPT=1`; every other value — or absence —
    /// keeps today's derived-key open). Parameterized on the environment so
    /// tests can pin both sides of the gate without mutating the process.
    static func rawKeyAdoptionEnabled(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> Bool {
        environment["GANCHO_RAWKEY_ADOPT"] == "1"
    }

    #if SQLITE_HAS_CODEC
        /// Re-encrypts a pre-encryption plaintext database in place.
        ///
        /// Older installs wrote `gancho.sqlite` unencrypted. On the first launch
        /// of an encrypting build we detect that file by its plaintext SQLite
        /// magic header, export it into a sibling encrypted database with
        /// `sqlcipher_export` (copying every table, index, and FTS row), and swap
        /// it in. No clip is lost. A no-op on a fresh install (no file) or an
        /// already-encrypted store (random header bytes).
        static func encryptPlaintextStoreIfNeeded(at path: String, passphrase: String) throws {
            let fileManager = FileManager.default
            guard fileManager.fileExists(atPath: path) else { return }  // fresh install

            // A plaintext database starts with the 16-byte SQLite magic header;
            // an encrypted one has random bytes there (we keep no plaintext header).
            guard let handle = FileHandle(forReadingAtPath: path) else { return }
            let header = try handle.read(upToCount: 16)
            try handle.close()
            guard header == Data("SQLite format 3\u{0}".utf8) else { return }  // already encrypted

            let encryptedPath = path + ".encrypting"
            try? fileManager.removeItem(atPath: encryptedPath)
            // Scope the plaintext connection so it closes before the file swap.
            do {
                let plaintext = try DatabaseQueue(path: path)
                try plaintext.inDatabase { db in
                    // Hex key has no quotes; escape defensively all the same.
                    let quotedPath = encryptedPath.replacingOccurrences(of: "'", with: "''")
                    let quotedKey = passphrase.replacingOccurrences(of: "'", with: "''")
                    try db.execute(
                        sql: "ATTACH DATABASE '\(quotedPath)' AS encrypted KEY '\(quotedKey)'")
                    try db.execute(sql: "SELECT sqlcipher_export('encrypted')")
                    try db.execute(sql: "DETACH DATABASE encrypted")
                }
            }

            // Swap the encrypted file in, dropping the plaintext file and any
            // stale WAL/SHM siblings that belong to the old database.
            try fileManager.removeItem(atPath: path)
            try? fileManager.removeItem(atPath: path + "-wal")
            try? fileManager.removeItem(atPath: path + "-shm")
            try fileManager.moveItem(atPath: encryptedPath, toPath: path)
        }
    #endif

    /// Injectable writer for tests (`DatabaseQueue()` in-memory).
    public init(writer: any DatabaseWriter, blobs: BlobStore) {
        self.writer = writer
        self.blobs = blobs
    }

    /// Tests call this for in-memory databases; the directory initializer
    /// migrates automatically. GRDB-shaped and NOT part of the frozen client
    /// contract — behind `@_spi(GanchoInternal)` so it leaves the app-facing and
    /// third-party public surface; opt in with `@_spi(GanchoInternal) import`.
    @_spi(GanchoInternal)
    public func migrate() throws {
        try migrator.migrate(writer)
    }

    /// Partial migration for the perf harness (e.g. populate at v1, then
    /// measure the FTS index build that v2 performs over existing rows).
    func migrate(upTo identifier: String) throws {
        try migrator.migrate(writer, upTo: identifier)
    }

    /// Bulk insert in ONE transaction — importers and synthetic fixtures.
    /// Skips dedupe on purpose: imports are presumed pre-deduplicated, and
    /// per-row lookups would turn 100k inserts into minutes.
    public func importBatch(_ entries: [(item: ClipItem, content: ClipContent?)]) async throws {
        var rows: [ClipRow] = []
        rows.reserveCapacity(entries.count)
        for entry in entries {
            var row = ClipRow(item: entry.item)
            switch entry.content {
            case .text(let text):
                row.contentText = text
            case .binary(let data, let typeIdentifier):
                row.contentBlobHash = try blobs.write(data)
                row.contentTypeIdentifier = typeIdentifier
            case .fileReferences(let paths):
                row.contentText = paths.joined(separator: "\n")
                row.contentTypeIdentifier = "public.file-url"
            case nil:
                break
            }
            rows.append(row)
        }
        let finalRows = rows
        try await writer.write { db in
            for row in finalRows {
                try row.insert(db)
            }
        }
    }

    /// Reclaims space after large deletes. Runs on GRDB's writer queue —
    /// never the main thread; the retention engine calls it after purges.
    public func vacuum() async throws {
        try await writer.writeWithoutTransaction { db in
            try db.execute(sql: "VACUUM")
        }
    }

    private var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1-clips") { db in
            try db.create(table: "clip") { t in
                t.primaryKey("id", .text)
                t.column("createdAt", .datetime).notNull().indexed()
                t.column("updatedAt", .datetime).notNull()
                t.column("lastUsedAt", .datetime)
                t.column("kind", .text).notNull()
                t.column("title", .text).notNull()
                t.column("preview", .text).notNull()
                t.column("contentHash", .text).notNull().indexed()
                t.column("sourceAppBundleID", .text)
                t.column("sourceDeviceName", .text)
                t.column("isPinned", .boolean).notNull().defaults(to: false)
                t.column("isSensitive", .boolean).notNull().defaults(to: false)
                t.column("expiresAt", .datetime)
                t.column("tags", .text).notNull().defaults(to: "[]")
                t.column("contentText", .text)
                t.column("contentBlobHash", .text)
                t.column("contentTypeIdentifier", .text)
            }
        }
        migrator.registerMigration("v2-fts") { db in
            // External-content FTS5 over the text columns; GRDB installs the
            // sync triggers so the index follows every write automatically.
            try db.create(virtualTable: "clip_fts", using: FTS5()) { t in
                t.synchronize(withTable: "clip")
                t.column("title")
                t.column("preview")
                t.column("contentText")
            }
        }
        migrator.registerMigration("v3-purge-log") { db in
            // Counters for the Privacy Center: what purges removed (numbers
            // and reasons only — content is gone and was never logged).
            try db.create(table: "purge_log") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("runAt", .datetime).notNull().indexed()
                t.column("totalRowsPurged", .integer).notNull()
                t.column("summary", .text).notNull()
            }
        }
        migrator.registerMigration("v4-pinboards") { db in
            try db.create(table: "pinboard") { t in
                t.primaryKey("id", .text)
                t.column("name", .text).notNull()
                t.column("sortIndex", .integer).notNull().defaults(to: 0)
                t.column("createdAt", .datetime).notNull()
            }
            try db.alter(table: "clip") { t in
                t.add(column: "pinboardID", .text).indexed()
                t.add(column: "sortIndex", .integer).notNull().defaults(to: 0)
            }
        }
        migrator.registerMigration("v5-archive") { db in
            // Free-tier overflow is ARCHIVED, never deleted — no data
            // hostage. Pro releases everything back.
            try db.alter(table: "clip") { t in
                t.add(column: "isArchived", .boolean).notNull().defaults(to: false)
            }
        }
        migrator.registerMigration("v6-snippets") { db in
            // The second world: snippets are CURATED and PERMANENT (exempt
            // from retention and tier archiving). A clip becomes one via
            // the promote gesture; same table, so search/dedupe stay one.
            try db.alter(table: "clip") { t in
                t.add(column: "isSnippet", .boolean).notNull().defaults(to: false)
            }
        }
        migrator.registerMigration("v7-embeddings") { db in
            // Sentence vectors for semantic search (Pro). float32 BLOB;
            // dimension recorded so model upgrades can re-embed selectively.
            try db.create(table: "clip_embedding") { t in
                t.primaryKey("clipID", .text)
                t.column("dimension", .integer).notNull()
                t.column("vector", .blob).notNull()
            }
        }
        migrator.registerMigration("v8-sync") { db in
            // CloudKit sync bookkeeping. `syncSystemFields` archives the
            // CKRecord metadata (change tag etc.) per row; NULL = never
            // synced (needs initial upload). `needsUpload` flags local edits
            // that must re-upload. Deletions become tombstones so they
            // propagate before the row is forgotten.
            try db.alter(table: "clip") { t in
                t.add(column: "syncSystemFields", .blob)
                t.add(column: "needsUpload", .boolean).notNull().defaults(to: false)
            }
            try db.create(table: "sync_tombstone") { t in
                t.primaryKey("recordID", .text)
                t.column("deletedAt", .datetime).notNull()
            }
        }
        migrator.registerMigration("v9-mcp-access-log") { db in
            // Local MCP/CLI access log for the Privacy Center: which tool ran,
            // under what scope, how many clips it exposed, and whether the
            // scope denied it — numbers only. The column set has no room for
            // content, so a future logging bug cannot leak a clip.
            try db.create(table: "mcp_access_log") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("occurredAt", .datetime).notNull().indexed()
                t.column("tool", .text).notNull()
                t.column("scope", .text).notNull()
                t.column("resultCount", .integer).notNull()
                t.column("wasDenied", .boolean).notNull().defaults(to: false)
            }
        }
        migrator.registerMigration("v10-boards") { db in
            // Boards become a first-class axis, independent of pinning: a clip
            // can belong to MANY boards, tracked in a junction. The legacy
            // single `pinboardID` column is migrated in and then left unused.
            // The migration itself is local schema work; later sync migrations
            // and record mapping carry boards and membership between devices.
            // Cascades clean the junction when a clip or board is gone.
            try db.alter(table: "pinboard") { t in
                t.add(column: "sfSymbol", .text).notNull().defaults(to: "square.stack")
            }
            try db.create(table: "clip_board") { t in
                t.column("clipID", .text).notNull().indexed()
                    .references("clip", onDelete: .cascade)
                t.column("boardID", .text).notNull().indexed()
                    .references("pinboard", onDelete: .cascade)
                t.primaryKey(["clipID", "boardID"])
            }
            try db.execute(
                sql: "INSERT OR IGNORE INTO clip_board (clipID, boardID) "
                    + "SELECT id, pinboardID FROM clip WHERE pinboardID IS NOT NULL")
        }
        migrator.registerMigration("v11-favorites") { db in
            // The built-in Favorites board: always present, sorts first, and is
            // immutable (rename/delete guard on `isSystem`). Its display name is
            // localized in the UI keyed on `isSystem`, not this seeded value.
            try db.alter(table: "pinboard") { t in
                t.add(column: "isSystem", .boolean).notNull().defaults(to: false)
            }
            try db.execute(
                sql: "INSERT OR IGNORE INTO pinboard "
                    + "(id, name, sfSymbol, sortIndex, createdAt, isSystem) "
                    + "VALUES (?, ?, ?, ?, ?, 1)",
                arguments: [
                    Pinboard.favoritesID.uuidString, "Favorites", "star", -1,
                    Date(timeIntervalSince1970: 0)
                ])
        }
        migrator.registerMigration("v12-board-sync") { db in
            // Board metadata syncs (owner design): mirror the clip's sync columns
            // on the board table so a board's name/glyph propagate between devices.
            // `needsUpload` defaults to 1 so boards predating sync upload on the
            // first synced run. The seeded Favorites is also marked — harmless,
            // it just re-asserts its (identical) metadata.
            try db.alter(table: "pinboard") { t in
                t.add(column: "syncSystemFields", .blob)
                t.add(column: "needsUpload", .boolean).notNull().defaults(to: true)
            }
        }
        migrator.registerMigration("v13-snippet-keyword") { db in
            // Snippets reuse the clip row (isSnippet); add the keyword they're
            // invoked by and a usage counter for the Library's stats.
            try db.alter(table: "clip") { t in
                t.add(column: "keyword", .text)
                t.add(column: "uses", .integer).notNull().defaults(to: 0)
            }
        }
        migrator.registerMigration("v14-board-tombstone") { db in
            // Board deletions need a tombstone so they propagate to other devices
            // (mirrors the clip `sync_tombstone`). Lives in the board zone, so it
            // is tracked separately from the clip tombstones.
            try db.create(table: "board_tombstone") { t in
                t.column("recordID", .text).primaryKey()
                t.column("deletedAt", .datetime).notNull()
            }
        }
        migrator.registerMigration("v15-reupload-board-members") { db in
            // Board membership rides the clip's sync record, but clips assigned
            // before that wiring landed have a stale (empty) board set in the
            // cloud. Re-flag every current member for upload so its record
            // carries the right boardIDs and the membership reaches other
            // devices. One-time; harmless when sync is off.
            try db.execute(
                sql: "UPDATE clip SET needsUpload = 1 "
                    + "WHERE id IN (SELECT DISTINCT clipID FROM clip_board)")
        }
        migrator.registerMigration("v16-hot-query-indexes") { db in
            // Indexes for the hottest read paths. Additive and correctness-
            // neutral: if the planner declines one, the query degrades to the
            // previous full-scan-and-sort plan — never to different results.
            //
            // idx_clip_recent_activity serves `items(offset:limit:)` — the list
            // refreshed after every capture, paste, pin, and sync settle. The
            // ordering expression must render exactly as GRDB emits
            // `(Column("lastUsedAt") ?? Column("createdAt")).desc`, i.e.
            // IFNULL(lastUsedAt, createdAt); a textual mismatch just means the
            // planner keeps the old full sort (see the graceful-degradation
            // note above). IFNULL is deterministic, as expression indexes need.
            try db.execute(
                sql: "CREATE INDEX IF NOT EXISTS idx_clip_recent_activity "
                    + "ON clip (isPinned DESC, IFNULL(lastUsedAt, createdAt) DESC) "
                    + "WHERE isArchived = 0")
            // idx_clip_browse serves `recentForBrowse(offset:limit:)` — the
            // panel's grouped history, the iOS recent list, and the keyboard
            // extension (which sorts inside a hard memory/CPU budget).
            try db.execute(
                sql: "CREATE INDEX IF NOT EXISTS idx_clip_browse "
                    + "ON clip (isPinned DESC, createdAt DESC) WHERE isArchived = 0")
            // idx_clip_board_board gives the junction a boardID-led COVERING
            // path: the board-filter subquery (`SELECT clipID FROM clip_board
            // WHERE boardID = ?`) and the retention engine's
            // `id NOT IN (SELECT clipID FROM clip_board)` membership checks
            // answer from the index alone. The v10 PK leads with clipID, and
            // v10's single-column boardID index still needs a table hop per
            // row to fetch clipID.
            try db.execute(
                sql: "CREATE INDEX IF NOT EXISTS idx_clip_board_board "
                    + "ON clip_board (boardID, clipID)")
            // idx_clip_sensitive turns `sensitiveCount()` (Privacy Center),
            // `deleteAllSensitive()` (panic actions), and the retention
            // engine's sensitive-expiry clause into O(matches) index lookups —
            // sensitive rows are a tiny slice of the table, so the partial
            // index stays tiny too.
            try db.execute(
                sql: "CREATE INDEX IF NOT EXISTS idx_clip_sensitive "
                    + "ON clip (isSensitive) WHERE isSensitive = 1")
        }
        migrator.registerMigration("v17-frecency-boards-insights") { db in
            // Frecency ranking, board identity, embedding versioning, and two
            // local-only tables (search history, per-app counters). All
            // additive; the indexes degrade gracefully like v16's.

            // Snippet keyword lookup runs `keyword = ? COLLATE NOCASE` filtered
            // by `isSnippet = 1` (SnippetLibrary) — today a filtered scan.
            try db.execute(
                sql: "CREATE INDEX IF NOT EXISTS idx_clip_keyword "
                    + "ON clip (keyword COLLATE NOCASE) WHERE isSnippet = 1")
            // Capture dedup looks up `(contentHash, sourceDeviceName)` on every
            // insert; the v1 single-column contentHash index needs a table hop.
            // Full (not partial) on purpose: the dedup query filters
            // `sourceDeviceName = ?`, which becomes `IS NULL` for locally
            // captured clips with no device name — a `WHERE ... IS NOT NULL`
            // partial index would exclude exactly those rows and force the NULL
            // case back onto the v1 contentHash index. contentHash leads, so the
            // full index serves both the `= value` and the `IS NULL` lookups.
            try db.execute(
                sql: "CREATE INDEX IF NOT EXISTS idx_clip_dedupe "
                    + "ON clip (contentHash, sourceDeviceName)")
            // Frecency (pinned first, then use count, then recency) backs the
            // search re-rank and a future "Frequent" rail.
            try db.execute(
                sql: "CREATE INDEX IF NOT EXISTS idx_clip_frecency "
                    + "ON clip (isPinned DESC, uses DESC, IFNULL(lastUsedAt, createdAt) DESC) "
                    + "WHERE isArchived = 0")
            // Board identity. colorHex is a fixed-palette token (plain, no
            // content); emoji is a user choice (rides encryptedValues in sync,
            // like the board name). Both sync — a change must mark the board
            // needsUpload and enqueue it.
            try db.alter(table: "pinboard") { t in
                t.add(column: "colorHex", .text)
                t.add(column: "emoji", .text)
            }
            // Embedding model version so a model upgrade can re-embed
            // selectively; existing vectors are version 1.
            try db.alter(table: "clip_embedding") { t in
                t.add(column: "modelVersion", .integer).notNull().defaults(to: 1)
            }
            // Search history — LOCAL ONLY, never synced. Capped in code (50 rows).
            // `query` is UNIQUE with the default ABORT policy (NOT ON CONFLICT
            // REPLACE): the recall API upserts explicitly
            // (`ON CONFLICT(query) DO UPDATE SET uses = uses + 1, lastUsedAt = ?`)
            // so re-searching a term BUMPS its counter. A schema-level REPLACE
            // would instead DELETE+INSERT a duplicate, silently resetting `uses`
            // to 1 — a footgun for any caller that forgets the upsert clause.
            try db.create(table: "search_history") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("query", .text).notNull().unique()
                t.column("uses", .integer).notNull().defaults(to: 1)
                t.column("lastUsedAt", .datetime).notNull()
            }
            // Per-app capture/paste counters for Insights — bundle id + counts
            // only, ZERO content. The column set has no room for clip text.
            try db.create(table: "clip_app_stats") { t in
                t.column("bundleID", .text).notNull()
                t.column("day", .text).notNull()
                t.column("captures", .integer).notNull().defaults(to: 0)
                t.column("pastes", .integer).notNull().defaults(to: 0)
                t.primaryKey(["bundleID", "day"])
            }
        }
        return migrator
    }

    // MARK: - Search (FTS5)

    /// Full-text search. Exact/fuzzy run on FTS5 (sanitized MATCH, ranked by
    /// BM25); regex scans the text columns with `NSRegularExpression`.
    /// Filters (kind / source app / date) apply to every mode.
    public func search(_ query: ClipSearchQuery, limit: Int = 50) async throws -> [ClipItem] {
        if query.mode == .regex {
            return try await regexSearch(query, limit: limit)
        }
        guard let match = query.ftsMatchExpression() else { return [] }

        return try await writer.read { db in
            var sql = """
                SELECT clip.* FROM clip
                JOIN clip_fts ON clip_fts.rowid = clip.rowid
                WHERE clip_fts MATCH ? AND clip.isArchived = 0
                """
            var arguments: [any DatabaseValueConvertible] = [match]
            Self.appendFilters(for: query, to: &sql, arguments: &arguments)
            sql += " ORDER BY bm25(clip_fts) LIMIT ?"
            arguments.append(limit)
            return try ClipRow.fetchAll(db, sql: sql, arguments: StatementArguments(arguments))
                .map(\.item)
        }
    }

    /// Regex mode examines at most this many rows per search. ICU's
    /// `NSRegularExpression` backtracks with no timeout, so a pathological
    /// pattern that matches nothing must not walk the whole table on the
    /// reader queue — the scan is bounded structurally instead.
    static let regexScanCeiling = 5000

    /// Regex mode matches at most this many characters of `contentText` per
    /// row (title/preview always match in full) — a bounded haystack caps the
    /// cost of catastrophic backtracking on a single giant clip.
    static let regexHaystackLimit = 100_000

    /// Regex search is BEST-EFFORT over recent items: the filtered scan stops
    /// after ``regexScanCeiling`` rows (newest first), and each row's
    /// `contentText` is matched only up to ``regexHaystackLimit`` characters.
    /// Both bounds keep a hostile pattern (ReDoS) from wedging the reader
    /// queue; narrowing filters (kind/app/date/board) extend the reach.
    private func regexSearch(_ query: ClipSearchQuery, limit: Int) async throws -> [ClipItem] {
        guard
            let regex = try? NSRegularExpression(
                pattern: query.text, options: [.caseInsensitive])
        else { throw ClipSearchError.invalidRegularExpression }

        return try await writer.read { db in
            var sql = "SELECT clip.* FROM clip WHERE clip.isArchived = 0"
            var arguments: [any DatabaseValueConvertible] = []
            Self.appendFilters(for: query, to: &sql, arguments: &arguments)
            sql += " ORDER BY createdAt DESC LIMIT ?"
            arguments.append(Self.regexScanCeiling)

            var results: [ClipItem] = []
            let cursor = try ClipRow.fetchCursor(
                db, sql: sql, arguments: StatementArguments(arguments))
            while let row = try cursor.next(), results.count < limit {
                let content = String((row.contentText ?? "").prefix(Self.regexHaystackLimit))
                let haystacks = [row.title, row.preview, content]
                let matches = haystacks.contains { text in
                    regex.firstMatch(
                        in: text, range: NSRange(text.startIndex..., in: text)) != nil
                }
                if matches {
                    results.append(row.item)
                }
            }
            return results
        }
    }

    /// Shared WHERE clauses for kind / source app / date filters.
    private static func appendFilters(
        for query: ClipSearchQuery, to sql: inout String,
        arguments: inout [any DatabaseValueConvertible]
    ) {
        if let kinds = query.kinds, !kinds.isEmpty {
            let placeholders = Array(repeating: "?", count: kinds.count).joined(separator: ",")
            sql += " AND clip.kind IN (\(placeholders))"
            arguments.append(contentsOf: kinds.map(\.rawValue).sorted())
        }
        if let app = query.sourceAppBundleID {
            sql += " AND clip.sourceAppBundleID = ?"
            arguments.append(app)
        }
        if let range = query.dateRange {
            sql += " AND clip.createdAt BETWEEN ? AND ?"
            arguments.append(range.lowerBound)
            arguments.append(range.upperBound)
        }
        if let boardID = query.boardID {
            sql += " AND clip.id IN (SELECT clipID FROM clip_board WHERE boardID = ?)"
            arguments.append(boardID.uuidString)
        }
    }

    // MARK: - ClipboardStore

    @discardableResult
    public func insert(_ item: ClipItem, content: ClipContent?) async throws -> ClipItem {
        var row = ClipRow(item: item)
        switch content {
        case .text(let text):
            row.contentText = text
        case .binary(let data, let typeIdentifier):
            row.contentBlobHash = try blobs.write(data)
            row.contentTypeIdentifier = typeIdentifier
        case .fileReferences(let paths):
            row.contentText = paths.joined(separator: "\n")
            row.contentTypeIdentifier = "public.file-url"
        case nil:
            break
        }
        let finalRow = row
        let stored = try await writer.write { db -> ClipRow in
            // Dedupe key: contentHash + sourceDeviceName. The device matters:
            // the same content synced FROM another device must keep its own
            // row, or sync would ping-pong "moved to top" updates forever.
            if var existing =
                try ClipRow
                .filter(Column("contentHash") == finalRow.contentHash)
                .filter(Column("sourceDeviceName") == finalRow.sourceDeviceName)
                .fetchOne(db)
            {
                existing.lastUsedAt = Date()
                existing.updatedAt = Date()
                // A fresh copy is fresh activity: if tier enforcement had
                // archived this row, re-copying it must surface it again —
                // otherwise the capture silently lands in the hidden set.
                existing.isArchived = false
                try existing.update(db)
                return existing
            }
            try finalRow.insert(db)
            return finalRow
        }
        return stored.item
    }

    public func items(offset: Int, limit: Int) async throws -> [ClipItem] {
        try await writer.read { db in
            try ClipRow
                .filter(Column("isArchived") == false)
                // Recency = the clip's last activity: lastUsedAt when it has been
                // re-copied/used, else its createdAt. A freshly captured clip has
                // a nil lastUsedAt, so ordering by lastUsedAt alone (NULLs last in
                // SQLite DESC) would sink new clips below any previously-used one
                // — COALESCE keeps the newest copy on top.
                .order(
                    Column("isPinned").desc,
                    (Column("lastUsedAt") ?? Column("createdAt")).desc
                )
                .limit(limit, offset: offset)
                .fetchAll(db)
                .map(\.item)
        }
    }

    /// Direct metadata lookup for App Entities and other identifier-based
    /// clients. Fetch order from SQLite is undefined, so restore caller order
    /// after the bounded primary-key query.
    public func items(ids: [UUID]) async throws -> [ClipItem] {
        guard !ids.isEmpty else { return [] }
        return try await writer.read { db in
            let rows =
                try ClipRow
                .filter(keys: Set(ids.map(\.uuidString)))
                .filter(Column("isArchived") == false)
                .fetchAll(db)
            let itemsByID = Dictionary(uniqueKeysWithValues: rows.map { ($0.item.id, $0.item) })
            return ids.compactMap { itemsByID[$0] }
        }
    }

    /// Recent items for the grouped history browse: pinned first (pins always
    /// sit at the top, even under "All clips"), then by capture time
    /// (`createdAt`) descending so the date buckets of the rest stay contiguous
    /// and the keyboard cursor matches the visual order. Non-archived; paginates
    /// like `items(offset:limit:)`.
    public func recentForBrowse(offset: Int, limit: Int) async throws -> [ClipItem] {
        try await writer.read { db in
            try ClipRow
                .filter(Column("isArchived") == false)
                .order(Column("isPinned").desc, Column("createdAt").desc)
                .limit(limit, offset: offset)
                .fetchAll(db)
                .map(\.item)
        }
    }

    /// Visible (non-archived) items — matches what lists show.
    public func count() async throws -> Int {
        try await writer.read { db in
            try ClipRow.filter(Column("isArchived") == false).fetchCount(db)
        }
    }

    public func delete(id: UUID) async throws {
        let blobHash = try await writer.write { db -> String? in
            let hash = try ClipRow
                .filter(key: id.uuidString)
                .fetchOne(db)?.contentBlobHash
            try ClipRow.deleteOne(db, key: id.uuidString)
            return hash
        }
        if let blobHash {
            // Content-addressed: only safe to remove when no other row
            // references the same bytes.
            let stillReferenced = try await writer.read { db in
                try ClipRow.filter(Column("contentBlobHash") == blobHash).fetchCount(db) > 0
            }
            if !stillReferenced {
                blobs.delete(hash: blobHash)
            }
        }
    }

    /// How many sensitive clips are currently held — the honest count behind the
    /// Privacy Center's "Secrets masked" stat (the old proxy counted clips whose
    /// preview literally rendered as the mask string, which under- and over-
    /// counted depending on the secret's shape).
    public func sensitiveCount() async throws -> Int {
        try await writer.read { db in
            // Exclude archived rows like `search` and the other dashboard
            // counters do, so "Secrets masked" agrees with the rest of them.
            try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM clip WHERE isSensitive = 1 AND isArchived = 0") ?? 0
        }
    }

    /// Removes every sensitive clip immediately ("Clear Sensitive" intent
    /// and panic actions). Returns how many were removed.
    @discardableResult
    public func deleteAllSensitive() async throws -> Int {
        let (removed, blobCandidates) = try await writer.write { db -> (Int, Set<String>) in
            // Capture the doomed rows' blob hashes BEFORE the delete so the
            // cleanup below is precise — O(deleted), not a directory sweep.
            let candidates = try String.fetchSet(
                db,
                sql: "SELECT DISTINCT contentBlobHash FROM clip "
                    + "WHERE isSensitive = 1 AND contentBlobHash IS NOT NULL")
            // Synced rows leave tombstones first so the panic delete also
            // removes the records from iCloud (via the pending-deletion queue)
            // instead of the secrets resurrecting on the next fetch.
            try db.execute(
                sql: "INSERT OR REPLACE INTO sync_tombstone (recordID, deletedAt) "
                    + "SELECT id, ? FROM clip "
                    + "WHERE isSensitive = 1 AND syncSystemFields IS NOT NULL",
                arguments: [Date()])
            try db.execute(sql: "DELETE FROM clip WHERE isSensitive = 1")
            return (db.changesCount, candidates)
        }
        _ = try await removeBlobsIfOrphaned(blobCandidates)
        return removed
    }

    public func content(for id: UUID) async throws -> ClipContent? {
        let row = try await writer.read { db in
            try ClipRow.filter(key: id.uuidString).fetchOne(db)
        }
        guard let row else { return nil }
        if let blobHash = row.contentBlobHash {
            guard let data = try blobs.read(hash: blobHash) else { return nil }
            return .binary(
                data: data, typeIdentifier: row.contentTypeIdentifier ?? "public.data")
        }
        if row.contentTypeIdentifier == "public.file-url", let text = row.contentText {
            return .fileReferences(text.split(separator: "\n").map(String.init))
        }
        if let text = row.contentText {
            return .text(text)
        }
        return nil
    }

    /// Lazy list-row thumbnail BYTES for binary clips; nil for text clips. The
    /// way app/extension readers should load thumbnails — it works for both
    /// plaintext and encrypted stores (decoding the small cached thumbnail,
    /// never the full blob once warmed).
    public func thumbnailData(for id: UUID) async throws -> Data? {
        let blobHash = try await writer.read { db in
            try ClipRow.filter(key: id.uuidString).fetchOne(db)?.contentBlobHash
        }
        guard let blobHash else { return nil }
        return try blobs.thumbnailData(for: blobHash)
    }

    /// Lazy list-row thumbnail FILE URL — for plaintext stores only; nil for
    /// text clips or encrypted stores, whose cache must stay sealed on disk.
    /// Prefer `thumbnailData(for:)` for rendering; this is the file-based path
    /// (and the seal-safety contract: a non-nil URL means the file is plaintext).
    /// Plaintext-only and NOT a client-contract facet requirement — behind
    /// `@_spi(GanchoInternal)` so it stays off the frozen public surface.
    @_spi(GanchoInternal)
    public func thumbnailURL(for id: UUID) async throws -> URL? {
        let blobHash = try await writer.read { db in
            try ClipRow.filter(key: id.uuidString).fetchOne(db)?.contentBlobHash
        }
        guard let blobHash else { return nil }
        return try blobs.thumbnailURL(for: blobHash)
    }

    // MARK: - Export (always available, every tier — no data hostage)

    /// Versioned JSON export: full metadata + text content; binary payloads
    /// referenced by content hash (the blobs directory travels alongside).
    public func exportJSON() async throws -> Data {
        try await exportJSON(excludeSensitive: false)
    }

    /// As ``exportJSON()``, optionally dropping detector-flagged sensitive
    /// clips — an export must not turn a short-expiry secret into permanent
    /// plaintext unless the caller explicitly opts in. (The zero-argument
    /// form keeps the `ClipboardStore` protocol contract unchanged.)
    ///
    /// Rows are gathered through a cursor into ONE exactly-sized array
    /// (capacity reserved from a COUNT in the same read), with sensitive rows
    /// skipped during the walk — no `fetchAll` growth over-allocation and no
    /// second filtered pass, so excluded rows never materialize at all. The
    /// document is still encoded in ONE shot, deliberately: streaming the
    /// encoder would mean hand-assembling the `.prettyPrinted`/`.sortedKeys`
    /// layout byte-for-byte, which is implementation-defined and would break
    /// existing exports' byte-compat (see `.audit/21-store-finish.md`).
    /// ``exportCSV(excludeSensitive:)`` is the fully streamed format.
    public func exportJSON(excludeSensitive: Bool) async throws -> Data {
        let rows = try await writer.read { db -> [ClipRow] in
            var rows: [ClipRow] = []
            rows.reserveCapacity(try ClipRow.fetchCount(db))
            let cursor = try ClipRow.order(Column("createdAt").asc).fetchCursor(db)
            while let row = try cursor.next() {
                if excludeSensitive && row.isSensitive { continue }
                rows.append(row)
            }
            return rows
        }
        return try ClipExporter.json(rows: rows, exportedAt: .now)
    }

    /// RFC-4180 CSV: metadata + text content (binaries listed by reference).
    public func exportCSV() async throws -> Data {
        try await exportCSV(excludeSensitive: false)
    }

    /// As ``exportCSV()``, optionally dropping detector-flagged sensitive
    /// clips (see ``exportJSON(excludeSensitive:)``).
    ///
    /// Streams rows through a cursor instead of `fetchAll` so a 100k-row
    /// export never materializes every `ClipRow` at once — only the output
    /// text accumulates. Same bytes as before: same order, same escaping.
    public func exportCSV(excludeSensitive: Bool) async throws -> Data {
        // Field escaping/assembly is centralized in ``ClipExporter``; the cursor
        // walk stays here so streaming is preserved. Byte-identical to before.
        try await writer.read { db -> Data in
            var csv = ClipExporter.csvHeader
            let cursor = try ClipRow.order(Column("createdAt").asc).fetchCursor(db)
            while let row = try cursor.next() {
                if excludeSensitive && row.isSensitive { continue }
                csv += ClipExporter.csvLine(for: row)
            }
            return Data(csv.utf8)
        }
    }
}

/// Database row ↔ domain mapping. Internal: the row schema is a storage
/// detail; everything outside speaks `ClipItem` + `ClipContent`.
struct ClipRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "clip"

    /// Shared coders for the `tags` JSON column (default options, so the
    /// stored bytes are unchanged). Hoisted because bulk import/read paths
    /// map thousands of rows — one coder each, not one per row; encode and
    /// decode calls are safe to share across threads.
    static let tagsEncoder = JSONEncoder()
    static let tagsDecoder = JSONDecoder()

    var id: String
    var createdAt: Date
    var updatedAt: Date
    var lastUsedAt: Date?
    var kind: String
    var title: String
    var preview: String
    var contentHash: String
    var sourceAppBundleID: String?
    var sourceDeviceName: String?
    var isPinned: Bool
    var isSensitive: Bool
    var expiresAt: Date?
    var tags: String
    var contentText: String?
    var contentBlobHash: String?
    var contentTypeIdentifier: String?
    var isArchived: Bool = false
    var isSnippet: Bool = false
    var keyword: String?
    var uses: Int = 0

    init(item: ClipItem) {
        id = item.id.uuidString
        createdAt = item.createdAt
        updatedAt = item.updatedAt
        lastUsedAt = item.lastUsedAt
        kind = item.kind.rawValue
        title = item.title
        preview = item.preview
        contentHash = item.contentHash
        sourceAppBundleID = item.sourceAppBundleID
        sourceDeviceName = item.sourceDeviceName
        isPinned = item.isPinned
        isSensitive = item.isSensitive
        expiresAt = item.expiresAt
        tags =
            (try? String(data: Self.tagsEncoder.encode(item.tags), encoding: .utf8) ?? "[]")
            ?? "[]"
        contentText = nil
        contentBlobHash = nil
        contentTypeIdentifier = nil
        keyword = item.keyword
        uses = item.uses
    }

    var item: ClipItem {
        ClipItem(
            id: UUID(uuidString: id) ?? UUID(),
            createdAt: createdAt,
            updatedAt: updatedAt,
            lastUsedAt: lastUsedAt,
            kind: ClipContentKind(rawValue: kind) ?? .text,
            title: title,
            preview: preview,
            contentHash: contentHash,
            sourceAppBundleID: sourceAppBundleID,
            sourceDeviceName: sourceDeviceName,
            isPinned: isPinned,
            isSensitive: isSensitive,
            expiresAt: expiresAt,
            tags: (try? Self.tagsDecoder.decode([String].self, from: Data(tags.utf8))) ?? [],
            keyword: keyword,
            uses: uses
        )
    }
}

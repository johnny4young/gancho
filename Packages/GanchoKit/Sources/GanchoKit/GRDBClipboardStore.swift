import Foundation
import GRDB

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
    public static func encrypted(
        directory: URL,
        keychainAccessGroup: String? = nil
    ) throws -> GRDBClipboardStore {
        let key = try KeychainPassphraseStore(accessGroup: keychainAccessGroup).loadOrCreateKey()
        return try GRDBClipboardStore(directory: directory, passphrase: key)
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
    /// migrates automatically.
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
            // Boards stay device-local (only `isPinned` syncs) — no sync schema
            // change. Cascades clean the junction when a clip or board is gone.
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
                    Date(timeIntervalSince1970: 0),
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

    private func regexSearch(_ query: ClipSearchQuery, limit: Int) async throws -> [ClipItem] {
        guard
            let regex = try? NSRegularExpression(
                pattern: query.text, options: [.caseInsensitive])
        else { throw ClipSearchError.invalidRegularExpression }

        return try await writer.read { db in
            var sql = "SELECT clip.* FROM clip WHERE clip.isArchived = 0"
            var arguments: [any DatabaseValueConvertible] = []
            Self.appendFilters(for: query, to: &sql, arguments: &arguments)
            sql += " ORDER BY createdAt DESC"

            var results: [ClipItem] = []
            let cursor = try ClipRow.fetchCursor(
                db, sql: sql, arguments: StatementArguments(arguments))
            while let row = try cursor.next(), results.count < limit {
                let haystacks = [row.title, row.preview, row.contentText ?? ""]
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
        let removed = try await writer.write { db in
            // Synced rows leave tombstones first so the panic delete also
            // removes the records from iCloud (via the pending-deletion queue)
            // instead of the secrets resurrecting on the next fetch.
            try db.execute(
                sql: "INSERT OR REPLACE INTO sync_tombstone (recordID, deletedAt) "
                    + "SELECT id, ? FROM clip "
                    + "WHERE isSensitive = 1 AND syncSystemFields IS NOT NULL",
                arguments: [Date()])
            try db.execute(sql: "DELETE FROM clip WHERE isSensitive = 1")
            return db.changesCount
        }
        _ = try await removeOrphanedBlobs()
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
    public func exportJSON(excludeSensitive: Bool) async throws -> Data {
        var rows = try await writer.read { db in
            try ClipRow.order(Column("createdAt").asc).fetchAll(db)
        }
        if excludeSensitive {
            rows.removeAll(where: \.isSensitive)
        }
        let payload = ExportDocument(version: 1, exportedAt: .now, clips: rows)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }

    /// RFC-4180 CSV: metadata + text content (binaries listed by reference).
    public func exportCSV() async throws -> Data {
        try await exportCSV(excludeSensitive: false)
    }

    /// As ``exportCSV()``, optionally dropping detector-flagged sensitive
    /// clips (see ``exportJSON(excludeSensitive:)``).
    public func exportCSV(excludeSensitive: Bool) async throws -> Data {
        var rows = try await writer.read { db in
            try ClipRow.order(Column("createdAt").asc).fetchAll(db)
        }
        if excludeSensitive {
            rows.removeAll(where: \.isSensitive)
        }
        let formatter = ISO8601DateFormatter()
        var csv =
            "id,createdAt,kind,title,preview,contentHash,sourceApp,isPinned,contentText,contentBlobHash\n"
        for row in rows {
            let fields = [
                row.id, formatter.string(from: row.createdAt), row.kind, row.title,
                row.preview, row.contentHash, row.sourceAppBundleID ?? "",
                row.isPinned ? "true" : "false", row.contentText ?? "",
                row.contentBlobHash ?? "",
            ]
            csv += fields.map(Self.csvEscape).joined(separator: ",") + "\n"
        }
        return Data(csv.utf8)
    }

    private static func csvEscape(_ field: String) -> String {
        // Formula-injection guard (OWASP CSV injection): clipboard text is
        // attacker-influenced by nature, and a field starting with = + - @
        // (or a leading tab/CR) executes as a formula when the CSV is opened
        // in Excel/Numbers/Sheets. Neutralize with a leading apostrophe —
        // spreadsheets then render the field as literal text.
        var field = field
        if let first = field.first, "=+-@\t\r".contains(first) {
            field = "'" + field
        }
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}

/// Database row ↔ domain mapping. Internal: the row schema is a storage
/// detail; everything outside speaks `ClipItem` + `ClipContent`.
struct ClipRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "clip"

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
            (try? String(data: JSONEncoder().encode(item.tags), encoding: .utf8) ?? "[]") ?? "[]"
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
            tags: (try? JSONDecoder().decode([String].self, from: Data(tags.utf8))) ?? [],
            keyword: keyword,
            uses: uses
        )
    }
}

/// Export envelope — versioned so future schema changes stay importable.
private struct ExportDocument: Codable {
    var version: Int
    var exportedAt: Date
    var clips: [ClipRow]
}

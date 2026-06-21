import Foundation
import GRDB

/// SQLite-backed source of truth for clip history (GRDB).
///
/// Layout decisions (see docs/ARCHITECTURE.md):
/// - Metadata + full TEXT content live in the `clip` table; binary payloads
///   live on disk via `BlobStore` (the row keeps a content-hash reference).
///   List queries page metadata only — blobs never ride along.
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
    public convenience init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pool = try DatabasePool(path: directory.appendingPathComponent("gancho.sqlite").path)
        self.init(
            writer: pool,
            blobs: BlobStore(directory: directory.appendingPathComponent("blobs")))
        try migrator.migrate(pool)
        try Self.reformatLegacyImagePreviews(in: pool)
    }

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

    /// Removes every sensitive clip immediately ("Clear Sensitive" intent
    /// and panic actions). Returns how many were removed.
    @discardableResult
    public func deleteAllSensitive() async throws -> Int {
        let removed = try await writer.write { db in
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

    /// Lazy list-row thumbnail for binary clips; nil for text clips.
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
        let rows = try await writer.read { db in
            try ClipRow.order(Column("createdAt").asc).fetchAll(db)
        }
        let payload = ExportDocument(version: 1, exportedAt: .now, clips: rows)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }

    /// RFC-4180 CSV: metadata + text content (binaries listed by reference).
    public func exportCSV() async throws -> Data {
        let rows = try await writer.read { db in
            try ClipRow.order(Column("createdAt").asc).fetchAll(db)
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

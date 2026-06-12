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

    /// Production store at a directory (database + blobs side by side).
    public convenience init(directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let pool = try DatabasePool(path: directory.appendingPathComponent("gancho.sqlite").path)
        self.init(
            writer: pool,
            blobs: BlobStore(directory: directory.appendingPathComponent("blobs")))
        try migrator.migrate(pool)
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
                WHERE clip_fts MATCH ?
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
            var sql = "SELECT clip.* FROM clip WHERE 1"
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
                .order(
                    Column("isPinned").desc, Column("lastUsedAt").desc, Column("createdAt").desc
                )
                .limit(limit, offset: offset)
                .fetchAll(db)
                .map(\.item)
        }
    }

    public func count() async throws -> Int {
        try await writer.read { db in
            try ClipRow.fetchCount(db)
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
            tags: (try? JSONDecoder().decode([String].self, from: Data(tags.utf8))) ?? []
        )
    }
}

/// Export envelope — versioned so future schema changes stay importable.
private struct ExportDocument: Codable {
    var version: Int
    var exportedAt: Date
    var clips: [ClipRow]
}

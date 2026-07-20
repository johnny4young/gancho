import Foundation
import GRDB

/// The canonical, append-only database history. Identifier raw values and case
/// order are compatibility contracts for every installed Gancho database.
enum GanchoDatabaseMigrator {
    enum Identifier: String, CaseIterable {
        case clips = "v1-clips"
        case fts = "v2-fts"
        case purgeLog = "v3-purge-log"
        case pinboards = "v4-pinboards"
        case archive = "v5-archive"
        case snippets = "v6-snippets"
        case embeddings = "v7-embeddings"
        case sync = "v8-sync"
        case mcpAccessLog = "v9-mcp-access-log"
        case boards = "v10-boards"
        case favorites = "v11-favorites"
        case boardSync = "v12-board-sync"
        case snippetKeyword = "v13-snippet-keyword"
        case boardTombstone = "v14-board-tombstone"
        case reuploadBoardMembers = "v15-reupload-board-members"
        case hotQueryIndexes = "v16-hot-query-indexes"
        case frecencyBoardsInsights = "v17-frecency-boards-insights"
        case ftsPrefixIndexes = "v18-fts-prefix-indexes"
        case mcpClientLedger = "v19-mcp-client-ledger"
        case privateActivityReceipt = "v20-private-activity-receipt"
    }

    static var identifiers: [String] {
        Identifier.allCases.map(\.rawValue)
    }

    static func make() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        registerInitialMigrations(in: &migrator)
        registerCurationMigrations(in: &migrator)
        registerSyncMigrations(in: &migrator)
        registerBoardLifecycleMigrations(in: &migrator)
        registerScaleMigrations(in: &migrator)
        GRDBClipboardStore.registerMCPClientLedgerMigration(in: &migrator)
        GRDBClipboardStore.registerPrivateActivityReceiptMigration(in: &migrator)
        return migrator
    }

    private static func registerInitialMigrations(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration(Identifier.clips.rawValue) { db in
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
        migrator.registerMigration(Identifier.fts.rawValue) { db in
            // External-content FTS5 over the text columns; GRDB installs the
            // sync triggers so the index follows every write automatically.
            try db.create(virtualTable: "clip_fts", using: FTS5()) { t in
                t.synchronize(withTable: "clip")
                t.column("title")
                t.column("preview")
                t.column("contentText")
            }
        }
        migrator.registerMigration(Identifier.purgeLog.rawValue) { db in
            // Counters for the Privacy Center: what purges removed (numbers
            // and reasons only — content is gone and was never logged).
            try db.create(table: "purge_log") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("runAt", .datetime).notNull().indexed()
                t.column("totalRowsPurged", .integer).notNull()
                t.column("summary", .text).notNull()
            }
        }
        migrator.registerMigration(Identifier.pinboards.rawValue) { db in
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
    }

    private static func registerCurationMigrations(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration(Identifier.archive.rawValue) { db in
            // Free-tier overflow is ARCHIVED, never deleted — no data
            // hostage. Pro releases everything back.
            try db.alter(table: "clip") { t in
                t.add(column: "isArchived", .boolean).notNull().defaults(to: false)
            }
        }
        migrator.registerMigration(Identifier.snippets.rawValue) { db in
            // The second world: snippets are CURATED and PERMANENT (exempt
            // from retention and tier archiving). A clip becomes one via
            // the promote gesture; same table, so search/dedupe stay one.
            try db.alter(table: "clip") { t in
                t.add(column: "isSnippet", .boolean).notNull().defaults(to: false)
            }
        }
        migrator.registerMigration(Identifier.embeddings.rawValue) { db in
            // Sentence vectors for semantic search (Pro). float32 BLOB;
            // dimension recorded so model upgrades can re-embed selectively.
            try db.create(table: "clip_embedding") { t in
                t.primaryKey("clipID", .text)
                t.column("dimension", .integer).notNull()
                t.column("vector", .blob).notNull()
            }
        }
    }

    private static func registerSyncMigrations(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration(Identifier.sync.rawValue) { db in
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
        migrator.registerMigration(Identifier.mcpAccessLog.rawValue) { db in
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
        migrator.registerMigration(Identifier.boards.rawValue) { db in
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
        migrator.registerMigration(Identifier.favorites.rawValue) { db in
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
    }

    private static func registerBoardLifecycleMigrations(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration(Identifier.boardSync.rawValue) { db in
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
        migrator.registerMigration(Identifier.snippetKeyword.rawValue) { db in
            // Snippets reuse the clip row (isSnippet); add the keyword they're
            // invoked by and a usage counter for the Library's stats.
            try db.alter(table: "clip") { t in
                t.add(column: "keyword", .text)
                t.add(column: "uses", .integer).notNull().defaults(to: 0)
            }
        }
        migrator.registerMigration(Identifier.boardTombstone.rawValue) { db in
            // Board deletions need a tombstone so they propagate to other devices
            // (mirrors the clip `sync_tombstone`). Lives in the board zone, so it
            // is tracked separately from the clip tombstones.
            try db.create(table: "board_tombstone") { t in
                t.column("recordID", .text).primaryKey()
                t.column("deletedAt", .datetime).notNull()
            }
        }
        migrator.registerMigration(Identifier.reuploadBoardMembers.rawValue) { db in
            // Board membership rides the clip's sync record, but clips assigned
            // before that wiring landed have a stale (empty) board set in the
            // cloud. Re-flag every current member for upload so its record
            // carries the right boardIDs and the membership reaches other
            // devices. One-time; harmless when sync is off.
            try db.execute(
                sql: "UPDATE clip SET needsUpload = 1 "
                    + "WHERE id IN (SELECT DISTINCT clipID FROM clip_board)")
        }
    }

    private static func registerScaleMigrations(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration(Identifier.hotQueryIndexes.rawValue) { db in
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
        migrator.registerMigration(Identifier.frecencyBoardsInsights.rawValue) { db in
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
            // Per-app capture/reuse counters for the private activity receipt —
            // bundle ID + counts only, ZERO content. The column set has no room
            // for clip text.
            try db.create(table: "clip_app_stats") { t in
                t.column("bundleID", .text).notNull()
                t.column("day", .text).notNull()
                t.column("captures", .integer).notNull().defaults(to: 0)
                t.column("pastes", .integer).notNull().defaults(to: 0)
                t.primaryKey(["bundleID", "day"])
            }
        }
        migrator.registerMigration(Identifier.ftsPrefixIndexes.rawValue) { db in
            // Keep the historical v2 migration immutable. Rebuild once here so
            // existing databases and fresh migration replays converge on the
            // same FTS definition without schema-string branching.
            try db.drop(table: "clip_fts")
            try db.dropFTS5SynchronizationTriggers(forTable: "clip_fts")
            try db.create(virtualTable: "clip_fts", using: FTS5()) { t in
                t.synchronize(withTable: "clip")
                // Type-to-search emits prefix queries. Index the short prefixes
                // that otherwise require broad term-range scans while users type.
                t.prefixes = [2, 3, 4]
                t.column("title")
                t.column("preview")
                t.column("contentText")
            }
        }
    }
}

import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("Canonical database migrations")
struct DatabaseMigrationTests {
    private static let legacyStartingPoints = [
        GanchoDatabaseMigrator.Identifier.clips.rawValue,
        GanchoDatabaseMigrator.Identifier.sync.rawValue,
        GanchoDatabaseMigrator.Identifier.hotQueryIndexes.rawValue
    ]

    @Test("Migration identifiers remain byte-for-byte compatible and ordered")
    func canonicalIdentifiers() {
        #expect(
            GanchoDatabaseMigrator.identifiers == [
                "v1-clips",
                "v2-fts",
                "v3-purge-log",
                "v4-pinboards",
                "v5-archive",
                "v6-snippets",
                "v7-embeddings",
                "v8-sync",
                "v9-mcp-access-log",
                "v10-boards",
                "v11-favorites",
                "v12-board-sync",
                "v13-snippet-keyword",
                "v14-board-tombstone",
                "v15-reupload-board-members",
                "v16-hot-query-indexes",
                "v17-frecency-boards-insights",
                "v18-fts-prefix-indexes",
                "v19-mcp-client-ledger",
                "v20-private-activity-receipt",
                "v21-discovery-sync-indexes"
            ])
        #expect(Set(GanchoDatabaseMigrator.identifiers).count == 21)
    }

    @Test(
        "v1, v8, and v16 stores preserve rows while upgrading to current",
        arguments: legacyStartingPoints)
    func legacyStoresUpgrade(_ startingPoint: String) async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try store.migrate(upTo: startingPoint)
        let clipID = try #require(UUID(uuidString: "11111111-2222-4333-8444-555555555555"))
        try await store.writer.write { db in
            try Self.insertLegacyClip(id: clipID, marker: startingPoint, in: db)
        }

        try store.migrate()

        let item = try #require(try await store.items().first { $0.id == clipID })
        #expect(item.preview == "legacy \(startingPoint)")
        #expect(try await store.content(for: clipID) == .text("body \(startingPoint)"))
        #expect(try await appliedMigrations(in: store) == GanchoDatabaseMigrator.identifiers)
        let receiptColumns = try await store.writer.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info('clip_app_stats')")
        }
        #expect(receiptColumns.contains("sensitiveItemsExpired"))
    }

    @Test("The v21 indexes are the ones the planner actually picks")
    func discoveryIndexesAreUsed() async throws {
        // An index the planner declines is not free — it is write cost on every
        // insert and update, paid forever, for nothing. So assert the plan, not
        // the index's existence. These were chosen by reading `EXPLAIN QUERY
        // PLAN` before and after; two other candidates were dropped because the
        // planner would not use them (the sync-pending OR predicate) or because
        // an existing index already served the query (the board EXISTS).
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("plan-\(UUID().uuidString)")))
        try store.migrate()
        // The planner needs rows and statistics; on an empty table it prefers a
        // scan no matter what indexes exist.
        try await store.importBatch(
            (0..<2_000).map { index in
                (
                    item: ClipItem(
                        kind: .text, title: "t\(index)", preview: "p\(index)",
                        contentHash: "h\(index)",
                        sourceAppBundleID: "com.app.\(index % 12)"),
                    content: ClipContent.text("body")
                )
            })
        try await store.writer.write { db in try db.execute(sql: "ANALYZE") }

        let plans = try await store.writer.read { db in
            (
                sourceApps: try String.fetchAll(
                    db,
                    sql: """
                        EXPLAIN QUERY PLAN
                        SELECT sourceAppBundleID AS bundleID, COUNT(*) AS clipCount,
                               MAX(createdAt) AS mostRecentCapture
                        FROM clip WHERE isArchived = 0 AND sourceAppBundleID IS NOT NULL
                          AND TRIM(sourceAppBundleID) <> ''
                        GROUP BY sourceAppBundleID
                        ORDER BY mostRecentCapture DESC, bundleID ASC LIMIT 8
                        """, adapter: ColumnMapping(["detail": "detail"])),
                embeddings: try String.fetchAll(
                    db,
                    sql: """
                        EXPLAIN QUERY PLAN
                        SELECT clipID FROM clip_embedding WHERE modelVersion < 99 LIMIT 16
                        """, adapter: ColumnMapping(["detail": "detail"]))
            )
        }

        #expect(
            plans.sourceApps.contains { $0.contains("idx_clip_source_app") },
            "source-app discovery fell back to: \(plans.sourceApps)")
        #expect(
            !plans.sourceApps.contains { $0.contains("TEMP B-TREE FOR GROUP BY") },
            "the group-by sort came back: \(plans.sourceApps)")
        #expect(
            plans.embeddings.contains { $0.contains("idx_clip_embedding_model") },
            "stale-embedding lookup fell back to: \(plans.embeddings)")
    }

    @Test("A failed migration rolls back its DDL and the canonical migrator resumes")
    func interruptedMigrationResumes() async throws {
        let (store, directory) = try makeStore()
        defer { try? FileManager.default.removeItem(at: directory) }
        try store.migrate(upTo: GanchoDatabaseMigrator.Identifier.mcpAccessLog.rawValue)
        try await store.writer.write { db in
            try db.create(table: "clip_board") { table in
                table.column("conflict", .text)
            }
        }

        #expect(throws: (any Error).self) {
            try store.migrate(upTo: GanchoDatabaseMigrator.Identifier.boards.rawValue)
        }

        let interruptedState = try await store.writer.read { db in
            let boardColumns = try String.fetchAll(
                db, sql: "SELECT name FROM pragma_table_info('pinboard')")
            let applied = try GanchoDatabaseMigrator.make().appliedMigrations(db)
            return (boardColumns, applied)
        }
        #expect(!interruptedState.0.contains("sfSymbol"))
        #expect(
            interruptedState.1
                == Array(
                    GanchoDatabaseMigrator.identifiers.prefix(
                        through: GanchoDatabaseMigrator.Identifier.mcpAccessLog.rawValue)))

        try await store.writer.write { db in
            try db.drop(table: "clip_board")
        }
        try store.migrate()

        #expect(try await appliedMigrations(in: store) == GanchoDatabaseMigrator.identifiers)
        let recoveredColumns = try await store.writer.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM pragma_table_info('clip_board')")
        }
        #expect(Set(recoveredColumns).isSuperset(of: ["clipID", "boardID"]))
    }

    #if SQLITE_HAS_CODEC
        @Test(
            "Encrypted v1, v8, and v16 fixtures upgrade with their content intact",
            arguments: legacyStartingPoints)
        func encryptedLegacyStoresUpgrade(_ startingPoint: String) async throws {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
                "encrypted-migration-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            let databaseURL = directory.appendingPathComponent("gancho.sqlite")
            let passphrase = String(repeating: "0123456789abcdef", count: 4)
            let clipID = try #require(
                UUID(uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE"))

            var configuration = Configuration()
            configuration.prepareDatabase { db in
                try db.usePassphrase(passphrase)
            }
            do {
                let queue = try DatabaseQueue(path: databaseURL.path, configuration: configuration)
                try GanchoDatabaseMigrator.make().migrate(queue, upTo: startingPoint)
                try await queue.write { db in
                    try Self.insertLegacyClip(id: clipID, marker: startingPoint, in: db)
                }
            }

            let store = try GRDBClipboardStore(directory: directory, passphrase: passphrase)

            #expect(try await store.content(for: clipID) == .text("body \(startingPoint)"))
            #expect(try await appliedMigrations(in: store) == GanchoDatabaseMigrator.identifiers)
            let header = try Data(contentsOf: databaseURL).prefix(16)
            #expect(header != Data("SQLite format 3\u{0}".utf8))
        }
    #endif

    private func makeStore() throws -> (GRDBClipboardStore, URL) {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "migration-fixture-\(UUID().uuidString)", isDirectory: true)
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(), blobs: BlobStore(directory: directory))
        return (store, directory)
    }

    private func appliedMigrations(in store: GRDBClipboardStore) async throws -> [String] {
        try await store.writer.read { db in
            try GanchoDatabaseMigrator.make().appliedMigrations(db)
        }
    }

    private static func insertLegacyClip(id: UUID, marker: String, in db: Database) throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        try db.execute(
            sql: """
                INSERT INTO clip (
                    id, createdAt, updatedAt, kind, title, preview, contentHash,
                    isPinned, isSensitive, tags, contentText
                ) VALUES (?, ?, ?, 'text', '', ?, ?, 0, 0, '[]', ?)
                """,
            arguments: [
                id.uuidString, date, date, "legacy \(marker)", "hash-\(marker)",
                "body \(marker)"
            ])
    }
}

extension Array where Element: Equatable {
    fileprivate func prefix(through element: Element) -> ArraySlice<Element> {
        guard let index = firstIndex(of: element) else { return [] }
        return self[...index]
    }
}

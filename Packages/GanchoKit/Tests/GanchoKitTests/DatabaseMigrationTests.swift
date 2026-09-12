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
                "v21-discovery-indexes",
                "v22-saved-filters"
            ])
        #expect(Set(GanchoDatabaseMigrator.identifiers).count == 22)
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

    /// A store carrying enough rows AND statistics for the planner to make a
    /// realistic choice. Both tables matter: an empty `clip_embedding` makes
    /// SQLite take any index that exists, which is how the first version of
    /// this test passed while proving nothing.
    private func makeAnalyzedStore() async throws -> GRDBClipboardStore {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("plan-\(UUID().uuidString)")))
        try store.migrate()
        let seeded = (0..<2_000).map { index in
            (
                item: ClipItem(
                    kind: .text, title: "t\(index)", preview: "p\(index)",
                    contentHash: "h\(index)",
                    sourceAppBundleID: "com.app.\(index % 12)"),
                content: ClipContent.text("body")
            )
        }
        try await store.importBatch(seeded)
        try await store.writer.write { db in
            // Written at the version `saveEmbedding` actually writes: the stale
            // predicate is `< currentVersion`, so its selectivity is the point.
            for entry in seeded {
                try db.execute(
                    sql: """
                        INSERT INTO clip_embedding (clipID, dimension, vector, modelVersion)
                        VALUES (?, ?, ?, ?)
                        """,
                    arguments: [
                        entry.item.id.uuidString, 4, Data(count: 16),
                        EmbeddingModelInfo.currentVersion
                    ])
            }
            try db.execute(sql: "ANALYZE")
        }
        return store
    }

    @Test("The v21 source-app index covers discovery, and keeps covering it")
    func sourceAppIndexCoversDiscovery() async throws {
        // An index the planner declines is not free — it is write cost on every
        // insert and update, paid forever, for nothing. So assert the plan, not
        // the index's existence. Two other candidates were dropped for exactly
        // that reason: the sync-pending OR predicate the planner would not use,
        // and the board EXISTS an existing index already served.
        let store = try await makeAnalyzedStore()
        let plan = try await store.writer.read { db in
            try String.fetchAll(
                db,
                sql: """
                    EXPLAIN QUERY PLAN
                    SELECT sourceAppBundleID AS bundleID, COUNT(*) AS clipCount,
                           MAX(createdAt) AS mostRecentCapture
                    FROM clip
                    WHERE isArchived = 0
                      AND sourceAppBundleID IS NOT NULL
                      AND TRIM(sourceAppBundleID) <> ''
                    GROUP BY sourceAppBundleID
                    ORDER BY mostRecentCapture DESC, bundleID ASC
                    LIMIT ?
                    """, arguments: [8], adapter: ColumnMapping(["detail": "detail"]))
        }

        // COVERING specifically. Narrowing the partial index to also require
        // `TRIM(sourceAppBundleID) <> ''` — which looks like a tidy-up, since
        // the query has that term — still uses the index but stops covering it,
        // so every group pays a table fetch. This assertion is what keeps that
        // from landing as a cleanup.
        #expect(
            plan.contains { $0.contains("COVERING INDEX idx_clip_source_app") },
            "source-app discovery fell back to: \(plan)")
        #expect(
            !plan.contains { $0.contains("TEMP B-TREE FOR GROUP BY") },
            "the group-by sort came back: \(plan)")
    }

    @Test("The v21 embedding index serves the real stale-vector query")
    func embeddingIndexServesTheStaleLookup() async throws {
        // Verbatim `staleEmbeddingClipIDs`, join and predicates included: the
        // join order decides whether this index is reachable at all. Driven
        // from `clip` instead, SQLite reaches the embeddings through the
        // primary-key autoindex and never touches `idx_clip_embedding_model`.
        //
        // The first version of this test asked
        // `SELECT clipID FROM clip_embedding WHERE modelVersion < 99` against
        // an empty table and passed for two unrelated wrong reasons: with no
        // rows the planner takes any index, and `< 99` matches every row, which
        // on real data makes it prefer a scan.
        let store = try await makeAnalyzedStore()
        let plan = try await store.writer.read { db in
            try String.fetchAll(
                db,
                sql: """
                    EXPLAIN QUERY PLAN
                    SELECT e.clipID FROM clip_embedding e
                    JOIN clip c ON c.id = e.clipID
                    WHERE e.modelVersion < ? AND c.isArchived = 0 AND c.isSensitive = 0
                    LIMIT ?
                    """,
                arguments: [EmbeddingModelInfo.currentVersion, 16],
                adapter: ColumnMapping(["detail": "detail"]))
        }

        #expect(
            plan.contains { $0.contains("idx_clip_embedding_model") },
            "stale-embedding lookup fell back to: \(plan)")
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

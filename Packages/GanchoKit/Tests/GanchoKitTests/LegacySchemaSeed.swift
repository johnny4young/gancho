import Foundation
import GRDB

@_spi(GanchoInternal) @testable import GanchoKit

/// Seeds a text clip with only the v1 columns, so migration tests can fill a
/// store stopped at an older migration without the current row shape.
enum LegacySchemaSeed {
    static func insertText(_ item: ClipItem, into store: GRDBClipboardStore) async throws {
        try await store.writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO clip (
                        id, createdAt, updatedAt, kind, title, preview, contentHash,
                        isPinned, isSensitive, tags, contentText)
                    VALUES (?, ?, ?, ?, ?, ?, ?, 0, 0, '[]', ?)
                    """,
                arguments: [
                    item.id.uuidString, item.createdAt, item.updatedAt, item.kind.rawValue,
                    item.title, item.preview, item.contentHash, item.preview
                ])
        }
    }

    /// Bulk insert naming ONLY the v1 columns. `ClipRow` does the field mapping
    /// (kind rawValue, tags JSON) so the stored format matches production; the
    /// raw SQL just narrows the column list to what the v1 schema has.
    static func insertTextBatch(
        _ fixtures: [(item: ClipItem, content: ClipContent?)], into store: GRDBClipboardStore
    ) async throws {
        try await store.writer.write { db in
            for entry in fixtures {
                var row = ClipRow(item: entry.item)
                if case .text(let text)? = entry.content { row.contentText = text }
                try db.execute(
                    sql: """
                        INSERT INTO clip
                          (id, createdAt, updatedAt, lastUsedAt, kind, title, preview,
                           contentHash, sourceAppBundleID, sourceDeviceName, isPinned,
                           isSensitive, expiresAt, tags, contentText)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        row.id, row.createdAt, row.updatedAt, row.lastUsedAt, row.kind,
                        row.title, row.preview, row.contentHash, row.sourceAppBundleID,
                        row.sourceDeviceName, row.isPinned, row.isSensitive,
                        row.expiresAt, row.tags, row.contentText
                    ])
            }
        }
    }

    /// The stored `CREATE VIRTUAL TABLE` text for the FTS index, which
    /// carries the `prefix=` option only after v18 rebuilds it.
    static func ftsDefinition(in reader: some DatabaseReader) async throws -> String? {
        try await reader.read { db in
            try String.fetchOne(db, sql: "SELECT sql FROM sqlite_master WHERE name = 'clip_fts'")
        }
    }

    #if SQLITE_HAS_CODEC
        /// Seeds an encrypted on-disk store stopped at `migration`, mirroring the
        /// production pool configuration so a later open meets the same file,
        /// page size, and journal mode it will meet in the app. Every connection
        /// is closed on return; the result is the FTS definition as seeded.
        @discardableResult
        static func seedEncryptedStore(
            at directory: URL, passphrase: String, upTo migration: String,
            fixtures: [(item: ClipItem, content: ClipContent?)]
        ) async throws -> String? {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            var configuration = Configuration()
            configuration.maximumReaderCount = 8
            configuration.prepareDatabase { db in try db.usePassphrase(passphrase) }
            let pool = try DatabasePool(
                path: directory.appendingPathComponent("gancho.sqlite").path,
                configuration: configuration)
            let store = GRDBClipboardStore(
                writer: pool,
                blobs: BlobStore(
                    directory: directory.appendingPathComponent("blobs"),
                    encryptionKeyData: BlobStore.encryptionKeyData(for: passphrase)))
            try store.migrate(upTo: migration)
            // The current row shape has columns an older table lacks.
            try await insertTextBatch(fixtures, into: store)
            let definition = try await ftsDefinition(in: pool)
            try pool.close()
            return definition
        }
    #endif
}

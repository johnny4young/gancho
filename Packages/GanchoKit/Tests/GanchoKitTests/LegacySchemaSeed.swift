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
}

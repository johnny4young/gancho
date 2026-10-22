import Foundation
import GRDB

extension GRDBClipboardStore {
    /// Fills pixel sizes for image rows stored before they were recorded at
    /// capture. Local only, like `backfillLegacyPreviews()`: no `updatedAt` or
    /// `needsUpload` change. An image ImageIO cannot read, or whose blob cannot
    /// be opened, is marked 0 × 0 so later launches skip it. Returns how many
    /// rows the batch settled; 0 means nothing is left.
    @discardableResult
    public func backfillImageSizes(batch limit: Int = 100) async throws -> Int {
        guard limit > 0 else { return 0 }
        let rows = try await writer.read { db in
            try ClipRow.fetchAll(
                db,
                sql: """
                    SELECT * FROM clip
                    WHERE kind = ? AND imageWidth IS NULL AND contentBlobHash IS NOT NULL
                    LIMIT ?
                    """,
                arguments: [ClipContentKind.image.rawValue, limit])
        }
        guard !rows.isEmpty else { return 0 }
        var sizes: [(id: String, width: Int, height: Int)] = []
        for row in rows {
            var size = (width: 0, height: 0)
            if case .binary(let data, _)? = try? content(from: row),
                let read = ClipImageInfo.pixelSize(of: data)
            {
                size = read
            }
            sizes.append((row.id, size.width, size.height))
        }
        let settled = sizes
        try await writer.write { db in
            for entry in settled {
                try db.execute(
                    sql: """
                        UPDATE clip SET imageWidth = ?, imageHeight = ?
                        WHERE id = ? AND imageWidth IS NULL
                        """,
                    arguments: [entry.width, entry.height, entry.id])
            }
        }
        return settled.count
    }
}

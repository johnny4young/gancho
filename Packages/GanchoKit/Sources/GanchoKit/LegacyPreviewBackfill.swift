import Foundation
import GRDB

extension GRDBClipboardStore {
    /// One-time cosmetic backfill: rewrites image previews captured before
    /// human-readable sizes — "Image (734053 bytes)" → "Image (717 KB)" — so
    /// existing (and synced-in) clips match newly captured ones. Idempotent:
    /// a reformatted row no longer matches the byte pattern, so later runs do
    /// no work.
    ///
    /// Deliberately NOT part of the store open: the `LIKE 'Image (% bytes)'`
    /// scan can't use an index, so running it inside the synchronous open
    /// taxed every cold launch (app, keyboard, widgets, CLI). Apps call this
    /// from a post-launch background task after the first frame is up.
    ///
    /// Local only — it does NOT bump `updatedAt`/`needsUpload`, so it never
    /// churns sync; each device reformats its own copies on first launch of the
    /// new build.
    public func backfillLegacyPreviews() async throws {
        try await writer.write { db in
            try Self.reformatLegacyImagePreviews(db: db)
        }
    }

    /// Synchronous variant over an injected writer (tests, tools).
    static func reformatLegacyImagePreviews(in writer: any DatabaseWriter) throws {
        try writer.write { db in
            try reformatLegacyImagePreviews(db: db)
        }
    }

    private static func reformatLegacyImagePreviews(db: Database) throws {
        let rows = try Row.fetchAll(
            db,
            sql: "SELECT id, preview FROM clip WHERE kind = ? AND preview LIKE ?",
            arguments: [ClipContentKind.image.rawValue, "Image (% bytes)"])
        for row in rows {
            guard let bytes = ByteSize.legacyImageByteCount(row["preview"]) else { continue }
            try db.execute(
                sql: "UPDATE clip SET preview = ? WHERE id = ?",
                arguments: ["Image (\(ByteSize.formatted(bytes)))", row["id"] as String])
        }
    }
}

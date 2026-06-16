import Foundation
import GRDB

extension GRDBClipboardStore {
    /// One-time cosmetic backfill: rewrites image previews captured before
    /// human-readable sizes — "Image (734053 bytes)" → "Image (717 KB)" — so
    /// existing (and synced-in) clips match newly captured ones. Runs on every
    /// open but is idempotent: a reformatted row no longer matches the byte
    /// pattern, so later launches do no work.
    ///
    /// Local only — it does NOT bump `updatedAt`/`needsUpload`, so it never
    /// churns sync; each device reformats its own copies on first launch of the
    /// new build.
    static func reformatLegacyImagePreviews(in writer: any DatabaseWriter) throws {
        try writer.write { db in
            let rows = try Row.fetchAll(
                db,
                sql: "SELECT id, preview FROM clip WHERE kind = ? AND preview LIKE ?",
                arguments: [ClipContentKind.image.rawValue, "Image (% bytes)"])
            for row in rows {
                guard let bytes = legacyByteCount(row["preview"]) else { continue }
                try db.execute(
                    sql: "UPDATE clip SET preview = ? WHERE id = ?",
                    arguments: ["Image (\(ByteSize.formatted(bytes)))", row["id"] as String])
            }
        }
    }

    /// The trailing digit run before `" bytes)"`. Handles both the bare
    /// "Image (N bytes)" and the older "Image (uti, N bytes)" shapes.
    static func legacyByteCount(_ preview: String) -> Int? {
        guard let tail = preview.range(of: " bytes)") else { return nil }
        let digits = String(
            preview[..<tail.lowerBound].reversed().prefix { $0.isNumber }.reversed())
        return Int(digits)
    }
}

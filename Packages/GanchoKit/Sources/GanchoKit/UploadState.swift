import Foundation
import GRDB

/// Per-clip iCloud upload state for the peek's sync chip. Metadata only: no
/// payload is read or decrypted.
public protocol UploadStateProviding: Sendable {
    /// Whether the clip still has to reach iCloud: never uploaded, or edited
    /// since its last upload. False for an unknown id.
    func isAwaitingUpload(id: UUID) async throws -> Bool
}

extension GRDBClipboardStore: UploadStateProviding {
    public func isAwaitingUpload(id: UUID) async throws -> Bool {
        try await writer.read { db in
            try Bool.fetchOne(
                db,
                sql: """
                    SELECT EXISTS(
                        SELECT 1 FROM clip
                        WHERE id = ? AND (syncSystemFields IS NULL OR needsUpload = 1))
                    """,
                arguments: [id.uuidString]) ?? false
        }
    }
}

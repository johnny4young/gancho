import Foundation
import GRDB

extension GRDBClipboardStore {
    public func unrecoverableLocalClipIDs() async throws -> [UUID] {
        let rows = try await writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, contentBlobHash FROM clip
                    WHERE contentBlobHash IS NOT NULL AND syncSystemFields IS NULL
                    ORDER BY createdAt ASC
                    """
            ).map { (id: $0["id"] as String, hash: $0["contentBlobHash"] as String) }
        }
        // Rows share content-addressed blobs, so each file is opened once.
        var verdicts: [String: Bool] = [:]
        var ids: [UUID] = []
        for row in rows {
            try Task.checkCancellation()
            let lost =
                verdicts[row.hash] ?? blobsForMaintenance.isSealedUnderAnotherKey(hash: row.hash)
            verdicts[row.hash] = lost
            if lost, let id = UUID(uuidString: row.id) { ids.append(id) }
        }
        return ids
    }
}

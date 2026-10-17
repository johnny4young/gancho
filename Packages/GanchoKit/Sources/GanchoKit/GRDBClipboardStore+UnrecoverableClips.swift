import Foundation
import GRDB

extension GRDBClipboardStore {
    /// Clip ids the last scan found unreadable, synced or not. Hidden so blob
    /// sweeps skip it, and inside blobs/ so a store-generation reset archives it too.
    static let keyCheckFile = ".key-check"

    public func unrecoverableLocalClipIDs() async throws -> [UUID] {
        try await lostClipIDs().local
    }

    public func unrecoverableSyncedClipIDs() async throws -> [UUID] {
        try await lostClipIDs().synced
    }

    /// The first call opens every blob; later calls recheck only the clips it
    /// found. `BlobStore.write` re-seals rather than reuses a file under another
    /// key, and the blob key derives from the database passphrase, so a new key
    /// comes with a new store generation.
    private func lostClipIDs() async throws -> (local: [UUID], synced: [UUID]) {
        let record = blobsForMaintenance.directory.appendingPathComponent(Self.keyCheckFile)
        let known = (try? Data(contentsOf: record))
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) }
            .map(Set.init)
        let rows = try await writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, contentBlobHash, syncSystemFields IS NOT NULL AS synced
                    FROM clip WHERE contentBlobHash IS NOT NULL
                    ORDER BY createdAt ASC
                    """
            ).map {
                (
                    id: $0["id"] as String, hash: $0["contentBlobHash"] as String,
                    synced: $0["synced"] as Bool
                )
            }
        }
        // Rows share content-addressed blobs, so each file is opened once.
        var verdicts: [String: Bool] = [:]
        var local: [UUID] = []
        var synced: [UUID] = []
        for row in rows where known?.contains(row.id) ?? true {
            try Task.checkCancellation()
            let lost =
                verdicts[row.hash] ?? blobsForMaintenance.isSealedUnderAnotherKey(hash: row.hash)
            verdicts[row.hash] = lost
            guard lost, let id = UUID(uuidString: row.id) else { continue }
            if row.synced { synced.append(id) } else { local.append(id) }
        }
        if let data = try? JSONEncoder().encode((local + synced).map(\.uuidString)) {
            try? data.write(to: record, options: .atomic)
        }
        return (local, synced)
    }
}

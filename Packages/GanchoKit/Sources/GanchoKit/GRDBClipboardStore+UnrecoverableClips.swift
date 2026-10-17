import Foundation
import GRDB

extension GRDBClipboardStore {
    /// Clip ids the last synced scan found unreadable. Hidden so blob sweeps
    /// skip it, and inside blobs/ so a store-generation reset archives it too.
    static let syncedKeyCheckFile = ".synced-key-check"

    public func unrecoverableLocalClipIDs() async throws -> [UUID] {
        try await lostClipIDs(synced: false, among: nil)
    }

    /// The first call opens every synced blob; later calls recheck only the
    /// clips it found. `BlobStore.write` re-seals rather than reuses a file
    /// under another key, and the blob key derives from the database
    /// passphrase, so a new key comes with a new store generation.
    public func unrecoverableSyncedClipIDs() async throws -> [UUID] {
        let record = blobsForMaintenance.directory
            .appendingPathComponent(Self.syncedKeyCheckFile)
        let known = (try? Data(contentsOf: record))
            .flatMap { try? JSONDecoder().decode([String].self, from: $0) }
        let lost = try await lostClipIDs(synced: true, among: known.map(Set.init))
        if let data = try? JSONEncoder().encode(lost.map(\.uuidString)) {
            try? data.write(to: record, options: .atomic)
        }
        return lost
    }

    private func lostClipIDs(
        synced: Bool, among candidates: Set<String>?
    ) async throws -> [UUID] {
        let rows = try await writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, contentBlobHash FROM clip
                    WHERE contentBlobHash IS NOT NULL
                        AND syncSystemFields IS \(synced ? "NOT NULL" : "NULL")
                    ORDER BY createdAt ASC
                    """
            ).map { (id: $0["id"] as String, hash: $0["contentBlobHash"] as String) }
        }
        // Rows share content-addressed blobs, so each file is opened once.
        var verdicts: [String: Bool] = [:]
        var ids: [UUID] = []
        for row in rows where candidates?.contains(row.id) ?? true {
            try Task.checkCancellation()
            let lost =
                verdicts[row.hash] ?? blobsForMaintenance.isSealedUnderAnotherKey(hash: row.hash)
            verdicts[row.hash] = lost
            if lost, let id = UUID(uuidString: row.id) { ids.append(id) }
        }
        return ids
    }
}

import Foundation
import GRDB

/// What the CloudKit adapter needs from the local store, expressed WITHOUT
/// importing CloudKit — so the boundary holds and the engine room stays
/// network-free. The adapter (in `GanchoSync`) is the only thing that turns
/// these into CKRecords.
///
/// Record identity = the clip's UUID string (one CKRecord per clip), so
/// remote upserts/deletions address rows by id, never by content hash.
public protocol SyncLocalStore: Sendable {
    /// Clips that still need uploading: never synced (no system fields) or
    /// edited since last upload.
    func pendingUploads() async throws -> [(item: ClipItem, content: ClipContent?)]
    /// Record IDs of deletions waiting to propagate (tombstones).
    func pendingDeletionRecordIDs() async throws -> [String]

    /// After a successful upload: store the CKRecord system fields and clear
    /// the dirty flag.
    func markUploaded(id: UUID, systemFields: Data) async throws
    /// Archived CKRecord system fields for a clip (nil = never synced).
    func systemFields(for id: UUID) async throws -> Data?
    /// Flags a locally-edited clip for re-upload.
    func markNeedsUpload(id: UUID) async throws

    /// Applies a remote change, last-writer-wins by `updatedAt`: a remote
    /// older than the local row is ignored (but its system fields are still
    /// stored so we don't fight it). Never flips `needsUpload`.
    func applyRemoteUpsert(
        _ item: ClipItem, content: ClipContent?, systemFields: Data)
        async throws
    /// Applies a remote deletion by record id.
    func applyRemoteDeletion(recordID: String) async throws
    /// Forgets a tombstone once its deletion has propagated.
    func clearTombstone(recordID: String) async throws

    /// Drops every clip's saved CloudKit identity and re-flags all rows for
    /// upload. Called when the server zone is reset/deleted or the iCloud
    /// account changes: the old record identities are gone, so the next sync
    /// must re-upload from scratch. Local clips are kept — only the sync
    /// linkage is forgotten.
    func forgetAllSyncFields() async throws

    /// The board ids a clip belongs to — read when building the clip's sync
    /// record so membership rides the clip (the boards extension implements it).
    func boardIDs(forClip clipID: UUID) async throws -> Set<UUID>
    /// Rebuilds a clip's board membership from a synced record, seeding a
    /// placeholder board for any id whose metadata hasn't synced yet.
    func setBoardMembership(clipID: UUID, boardIDs: Set<UUID>) async throws

    // Board metadata sync — the board table's mirror of the clip methods above,
    // so a board's name/glyph propagate. Membership rides the clip record.
    func pendingBoardUploads() async throws -> [Pinboard]
    func markBoardNeedsUpload(id: UUID) async throws
    func markBoardUploaded(id: UUID, systemFields: Data) async throws
    func boardSystemFields(for id: UUID) async throws -> Data?
    func applyRemoteBoardUpsert(_ board: Pinboard, systemFields: Data) async throws
    func forgetAllBoardSyncFields() async throws

    // Board deletion sync — the board zone's tombstones, mirroring the clip
    // deletion methods so a deleted board disappears on the user's other devices.
    func pendingBoardDeletionRecordIDs() async throws -> [String]
    func applyRemoteBoardDeletion(recordID: String) async throws
    func clearBoardTombstone(recordID: String) async throws
}

extension GRDBClipboardStore: SyncLocalStore {
    public func pendingUploads() async throws -> [(item: ClipItem, content: ClipContent?)] {
        let rows = try await writer.read { db in
            try ClipRow.fetchAll(
                db,
                sql: """
                    SELECT * FROM clip
                    WHERE syncSystemFields IS NULL OR needsUpload = 1
                    ORDER BY createdAt ASC
                    """)
        }
        var result: [(ClipItem, ClipContent?)] = []
        for row in rows {
            result.append((row.item, try await content(for: row.item.id)))
        }
        return result
    }

    public func pendingDeletionRecordIDs() async throws -> [String] {
        try await writer.read { db in
            try String.fetchAll(db, sql: "SELECT recordID FROM sync_tombstone")
        }
    }

    public func markUploaded(id: UUID, systemFields: Data) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "UPDATE clip SET syncSystemFields = ?, needsUpload = 0 WHERE id = ?",
                arguments: [systemFields, id.uuidString])
        }
    }

    public func systemFields(for id: UUID) async throws -> Data? {
        try await writer.read { db in
            try Data.fetchOne(
                db, sql: "SELECT syncSystemFields FROM clip WHERE id = ?",
                arguments: [id.uuidString])
        }
    }

    public func markNeedsUpload(id: UUID) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "UPDATE clip SET needsUpload = 1 WHERE id = ?",
                arguments: [id.uuidString])
        }
    }

    public func applyRemoteUpsert(
        _ item: ClipItem, content: ClipContent?, systemFields: Data
    ) async throws {
        var row = ClipRow(item: item)
        switch content {
        case .text(let text):
            row.contentText = text
        case .binary(let data, let typeIdentifier):
            row.contentBlobHash = try blobsForMaintenance.write(data)
            row.contentTypeIdentifier = typeIdentifier
        case .fileReferences(let paths):
            row.contentText = paths.joined(separator: "\n")
            row.contentTypeIdentifier = "public.file-url"
        case nil:
            break
        }
        let finalRow = row
        try await writer.write { db in
            // Last-writer-wins: skip if the local copy is newer, but still
            // record the remote's system fields so we stop re-sending ours.
            if let localUpdatedAt = try Date.fetchOne(
                db, sql: "SELECT updatedAt FROM clip WHERE id = ?",
                arguments: [item.id.uuidString]),
                localUpdatedAt > item.updatedAt
            {
                try db.execute(
                    sql: "UPDATE clip SET syncSystemFields = ? WHERE id = ?",
                    arguments: [systemFields, item.id.uuidString])
                return
            }
            try finalRow.upsert(db)
            try db.execute(
                sql: "UPDATE clip SET syncSystemFields = ?, needsUpload = 0 WHERE id = ?",
                arguments: [systemFields, item.id.uuidString])
        }
    }

    public func applyRemoteDeletion(recordID: String) async throws {
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM clip WHERE id = ?", arguments: [recordID])
        }
    }

    public func clearTombstone(recordID: String) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "DELETE FROM sync_tombstone WHERE recordID = ?", arguments: [recordID])
        }
    }

    public func forgetAllSyncFields() async throws {
        try await writer.write { db in
            try db.execute(sql: "UPDATE clip SET syncSystemFields = NULL, needsUpload = 1")
        }
    }

    // MARK: Board metadata sync

    public func pendingBoardUploads() async throws -> [Pinboard] {
        try await writer.read { db in
            try PinboardRow.filter(sql: "needsUpload = 1").fetchAll(db).map(\.board)
        }
    }

    public func markBoardNeedsUpload(id: UUID) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "UPDATE pinboard SET needsUpload = 1 WHERE id = ?", arguments: [id.uuidString])
        }
    }

    public func markBoardUploaded(id: UUID, systemFields: Data) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "UPDATE pinboard SET syncSystemFields = ?, needsUpload = 0 WHERE id = ?",
                arguments: [systemFields, id.uuidString])
        }
    }

    public func boardSystemFields(for id: UUID) async throws -> Data? {
        try await writer.read { db in
            try Data.fetchOne(
                db, sql: "SELECT syncSystemFields FROM pinboard WHERE id = ?",
                arguments: [id.uuidString])
        }
    }

    public func applyRemoteBoardUpsert(_ board: Pinboard, systemFields: Data) async throws {
        try await writer.write { db in
            // Upsert metadata WITHOUT flipping needsUpload (remote-driven). isSystem
            // is left untouched so a device's local Favorites stays a system board.
            try db.execute(
                sql: """
                    INSERT INTO pinboard
                        (id, name, sfSymbol, sortIndex, createdAt, isSystem, syncSystemFields, \
                    needsUpload)
                    VALUES (?, ?, ?, ?, ?, ?, ?, 0)
                    ON CONFLICT(id) DO UPDATE SET
                        name = excluded.name, sfSymbol = excluded.sfSymbol,
                        sortIndex = excluded.sortIndex,
                        syncSystemFields = excluded.syncSystemFields, needsUpload = 0
                    """,
                arguments: [
                    board.id.uuidString, board.name, board.sfSymbol, board.sortIndex,
                    board.createdAt, board.isSystem, systemFields,
                ])
        }
    }

    public func forgetAllBoardSyncFields() async throws {
        try await writer.write { db in
            try db.execute(sql: "UPDATE pinboard SET syncSystemFields = NULL, needsUpload = 1")
        }
    }

    /// Records a deletion as a tombstone AND removes the row — call this
    /// instead of `delete(id:)` when sync is active so the deletion can
    /// propagate before the row is forgotten.
    public func deleteForSync(id: UUID, now: Date = .now) async throws {
        try await writer.write { db in
            try db.execute(
                sql:
                    "INSERT OR REPLACE INTO sync_tombstone (recordID, deletedAt) VALUES (?, ?)",
                arguments: [id.uuidString, now])
            try db.execute(sql: "DELETE FROM clip WHERE id = ?", arguments: [id.uuidString])
        }
    }

    /// How many clips have been uploaded to iCloud (carry stored system
    /// fields). Drives the Privacy Center "Items synchronized" count.
    public func syncedCount() async throws -> Int {
        try await writer.read { db in
            try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM clip WHERE syncSystemFields IS NOT NULL") ?? 0
        }
    }
}

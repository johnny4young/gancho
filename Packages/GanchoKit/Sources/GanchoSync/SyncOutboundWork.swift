import CloudKit
import Foundation
import GanchoKit

/// Store operations used by the real delegate, without manufacturing CloudKit
/// event objects. A failed read is never an empty queue or a missing record.
/// An unreadable row is reported as unreadable, never as absent.
struct SyncOutboundWork: Sendable {
    let store: any SyncLocalStore
    let clipZone: CKRecordZone.ID
    let boardZone: CKRecordZone.ID
    let maxAssetBytes: Int

    func pending() async throws -> SyncPendingWork {
        try await SyncPendingWork(
            clipUploadIDs: store.pendingUploadIDs(),
            clipDeletionRecordNames: store.pendingDeletionRecordIDs(),
            boardUploadIDs: store.pendingBoardUploads().map(\.id),
            boardDeletionRecordNames: store.pendingBoardDeletionRecordIDs())
    }

    func pendingCount() async throws -> Int {
        let clips = try await store.pendingUploadCount()
        let deletions = try await store.pendingDeletionRecordIDs().count
        let boards = try await store.pendingBoardUploads().count
        let boardDeletions = try await store.pendingBoardDeletionRecordIDs().count
        return clips + deletions + boards + boardDeletions
    }

    struct PreparedUploads {
        var records: [CKRecord.ID: CKRecord] = [:]
        /// Saves that could not be prepared; any local row behind one stays dirty.
        var unreadable: Set<CKRecord.ID> = []
    }

    /// One unreadable row is skipped so it cannot hold back every later batch.
    /// A failure the store itself reproduces is a store failure and throws.
    func prepare(_ ids: [CKRecord.ID]) async throws -> PreparedUploads {
        var boards: [UUID: Pinboard] = [:]
        if ids.contains(where: { $0.zoneID == boardZone }) {
            for board in try await store.pendingBoardUploads() { boards[board.id] = board }
        }
        var prepared = PreparedUploads()
        do {
            for recordID in ids {
                try Task.checkCancellation()
                do {
                    guard let record = try await record(for: recordID, boards: boards) else {
                        continue
                    }
                    prepared.records[recordID] = record
                } catch is CancellationError {
                    throw CancellationError()
                } catch {
                    _ = try await store.pendingUploadCount()
                    prepared.unreadable.insert(recordID)
                }
            }
            return prepared
        } catch {
            // No batch will consume these assets after a failed preparation.
            for record in prepared.records.values {
                ClipRecordMapper.removeStagedAsset(for: record)
            }
            throw error
        }
    }

    private func record(
        for recordID: CKRecord.ID, boards: [UUID: Pinboard]
    ) async throws
        -> CKRecord?
    {
        // No local row can stand behind a malformed or foreign record ID.
        guard let id = UUID(uuidString: recordID.recordName) else { return nil }
        // Undecodable saved system fields fall back to a fresh record;
        // the server's conflict reply then restores a valid change tag.
        if recordID.zoneID == boardZone {
            guard let board = boards[id] else { return nil }
            let fields = try await store.boardSystemFields(for: id)
            return BoardRecordMapper.record(for: board, systemFields: fields, zoneID: boardZone)
                ?? BoardRecordMapper.record(for: board, systemFields: nil, zoneID: boardZone)
        }
        guard recordID.zoneID == clipZone else { return nil }
        // The store already holds secrets back; a record is never built for one.
        guard let entry = try await store.pendingUpload(id: id), !entry.item.isSensitive else {
            return nil
        }
        let fields = try await store.systemFields(for: id)
        let membership = Array(try await store.boardIDs(forClip: id))
        return ClipRecordMapper.record(
            for: entry.item, content: entry.content, systemFields: fields,
            zoneID: clipZone, maxAssetBytes: maxAssetBytes, boardIDs: membership)
            ?? ClipRecordMapper.record(
                for: entry.item, content: entry.content, systemFields: nil,
                zoneID: clipZone, maxAssetBytes: maxAssetBytes, boardIDs: membership)
    }

    func acknowledge(_ record: CKRecord) async throws {
        if record.recordType == BoardRecordMapper.recordType {
            guard let board = BoardRecordMapper.decode(record) else {
                throw SyncOutboundFailure.invalidRecord
            }
            try await store.markBoardUploaded(
                id: board.id, systemFields: BoardRecordMapper.encodeSystemFields(record),
                uploaded: board)
        } else {
            // CloudKit has finished reading the asset even if local ack fails.
            defer { ClipRecordMapper.removeStagedAsset(for: record) }
            guard let id = UUID(uuidString: record.recordID.recordName),
                let revision = record["updatedAt"] as? Date
            else { throw SyncOutboundFailure.invalidRecord }
            try await store.markUploaded(
                id: id, systemFields: ClipRecordMapper.encodeSystemFields(record),
                uploadedAt: revision)
        }
    }

    func acknowledgeDeletion(_ id: CKRecord.ID) async throws {
        if id.zoneID == boardZone {
            try await store.clearBoardTombstone(recordID: id.recordName)
        } else if id.zoneID == clipZone {
            try await store.clearTombstone(recordID: id.recordName)
        } else {
            throw SyncOutboundFailure.invalidRecord
        }
    }

    /// The given saves whose local rows are still dirty: a newer local edit
    /// behind an acknowledgement, or an applied server copy whose membership
    /// rebuild dropped a board with a pending local deletion. Reads only the
    /// save queues those records can be in. Zones match by name and the result
    /// carries this device's own zone IDs, the form `prepare` accepts.
    func stillDirty(_ recordIDs: Set<CKRecord.ID>) async throws -> Set<CKRecord.ID> {
        let clips =
            recordIDs.contains { $0.zoneID.zoneName == clipZone.zoneName }
            ? Set(try await store.pendingUploadIDs()) : []
        let boards =
            recordIDs.contains { $0.zoneID.zoneName == boardZone.zoneName }
            ? Set(try await store.pendingBoardUploads().map(\.id)) : []
        return Set(
            recordIDs.compactMap { recordID -> CKRecord.ID? in
                guard let id = UUID(uuidString: recordID.recordName) else { return nil }
                switch recordID.zoneID.zoneName {
                case clipZone.zoneName where clips.contains(id):
                    return CKRecord.ID(recordName: id.uuidString, zoneID: clipZone)
                case boardZone.zoneName where boards.contains(id):
                    return CKRecord.ID(recordName: id.uuidString, zoneID: boardZone)
                default: return nil
                }
            })
    }

    /// True means the record needs sending again — a verified local win, or a
    /// server copy that applied but left the row dirty — never a failed apply.
    func resolveConflict(_ record: CKRecord) async throws -> Bool {
        if record.recordType == BoardRecordMapper.recordType {
            guard let board = BoardRecordMapper.decode(record) else {
                throw SyncOutboundFailure.invalidRecord
            }
            try await store.applyRemoteBoardUpsert(
                board, systemFields: BoardRecordMapper.encodeSystemFields(record))
            return false  // Boards retain their existing server-wins contract.
        }
        guard let decoded = ClipRecordMapper.decode(record) else {
            throw SyncOutboundFailure.invalidRecord
        }
        let boardIDs = Set(ClipRecordMapper.boardIDs(from: record))
        let summary = try await store.applyRemoteChanges(
            clips: [
                .init(
                    item: decoded.item, content: decoded.content,
                    systemFields: ClipRecordMapper.encodeSystemFields(record),
                    boardIDs: boardIDs)
            ],
            boards: [], clipDeletions: [], boardDeletions: [])
        guard summary.failed == 0 else { throw SyncOutboundFailure.localWrite }
        if summary.skippedAsStale > 0 {
            // A pending deletion also rejects a server copy. Only a surviving
            // dirty row needs a save; a tombstone must retain its delete intent.
            return try await !stillDirty([record.recordID]).isEmpty
        }
        // A plain server win is clean, so this cannot loop. Only a membership
        // rebuild that dropped a board re-flags the applied row, so the queue
        // is read just then: a resync full of server wins must not scan it per
        // record. The apply has committed, so an unreadable state re-sends
        // instead of reporting a failed apply; preparation skips a clean row.
        do {
            guard try await store.boardIDs(forClip: decoded.item.id) != boardIDs else {
                return false
            }
            return try await !stillDirty([record.recordID]).isEmpty
        } catch {
            return true
        }
    }
}

enum SyncOutboundFailure: Error {
    case invalidRecord
    case localWrite
}

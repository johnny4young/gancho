import CloudKit
import Foundation
import GanchoKit

/// Store operations used by the real delegate, without manufacturing CloudKit
/// event objects. A failed read is never an empty queue or a missing record.
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

    func prepare(_ ids: [CKRecord.ID]) async throws -> [CKRecord.ID: CKRecord] {
        var boards: [UUID: Pinboard] = [:]
        if ids.contains(where: { $0.zoneID == boardZone }) {
            for board in try await store.pendingBoardUploads() { boards[board.id] = board }
        }
        var records: [CKRecord.ID: CKRecord] = [:]
        do {
            for recordID in ids {
                try Task.checkCancellation()
                guard let id = UUID(uuidString: recordID.recordName) else {
                    throw SyncOutboundFailure.invalidRecord
                }
                let record: CKRecord?
                if recordID.zoneID == boardZone {
                    guard let board = boards[id] else { continue }
                    record = try await BoardRecordMapper.record(
                        for: board, systemFields: store.boardSystemFields(for: id),
                        zoneID: boardZone)
                } else if recordID.zoneID == clipZone {
                    guard let entry = try await store.pendingUpload(id: id) else { continue }
                    let fields = try await store.systemFields(for: id)
                    let membership = try await store.boardIDs(forClip: id)
                    record = ClipRecordMapper.record(
                        for: entry.item, content: entry.content, systemFields: fields,
                        zoneID: clipZone, maxAssetBytes: maxAssetBytes, boardIDs: Array(membership))
                } else {
                    throw SyncOutboundFailure.invalidRecord
                }
                guard let record else { throw SyncOutboundFailure.invalidRecord }
                records[recordID] = record
            }
            return records
        } catch {
            // No batch will consume these assets after a failed preparation.
            for record in records.values { ClipRecordMapper.removeStagedAsset(for: record) }
            throw error
        }
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

    /// True means a verified local win needs sending again, never a failed apply.
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
        let summary = try await store.applyRemoteChanges(
            clips: [
                .init(
                    item: decoded.item, content: decoded.content,
                    systemFields: ClipRecordMapper.encodeSystemFields(record),
                    boardIDs: Set(ClipRecordMapper.boardIDs(from: record)))
            ],
            boards: [], clipDeletions: [], boardDeletions: [])
        guard summary.failed == 0 else { throw SyncOutboundFailure.localWrite }
        return summary.skippedAsStale > 0
    }
}

enum SyncOutboundFailure: Error {
    case invalidRecord
    case localWrite
}

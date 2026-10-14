import CloudKit
import Foundation

/// Content-free snapshot of work the local store still considers unsynced.
/// It centralizes record-ID planning so restart and reconciliation cannot
/// silently disagree about which rows belong in CloudKit's queue.
struct SyncPendingWork: Equatable, Sendable {
    var clipUploadIDs: [UUID] = []
    var clipDeletionRecordNames: [String] = []
    var boardUploadIDs: [UUID] = []
    var boardDeletionRecordNames: [String] = []

    func changes(
        clipZoneID: CKRecordZone.ID,
        boardZoneID: CKRecordZone.ID
    ) -> [CKSyncEngine.PendingRecordZoneChange] {
        let clipUploads = clipUploadIDs.map {
            CKSyncEngine.PendingRecordZoneChange.saveRecord(
                CKRecord.ID(recordName: $0.uuidString, zoneID: clipZoneID))
        }
        let clipDeletions = clipDeletionRecordNames.compactMap { recordName in
            UUID(uuidString: recordName).map {
                CKSyncEngine.PendingRecordZoneChange.deleteRecord(
                    CKRecord.ID(recordName: $0.uuidString, zoneID: clipZoneID))
            }
        }
        let boardUploads = boardUploadIDs.map {
            CKSyncEngine.PendingRecordZoneChange.saveRecord(
                CKRecord.ID(recordName: $0.uuidString, zoneID: boardZoneID))
        }
        let boardDeletions = boardDeletionRecordNames.compactMap { recordName in
            UUID(uuidString: recordName).map {
                CKSyncEngine.PendingRecordZoneChange.deleteRecord(
                    CKRecord.ID(recordName: $0.uuidString, zoneID: boardZoneID))
            }
        }
        return clipUploads + clipDeletions + boardUploads + boardDeletions
    }

    func staleSaveChanges(
        in pendingChanges: [CKSyncEngine.PendingRecordZoneChange],
        clipZoneID: CKRecordZone.ID,
        boardZoneID: CKRecordZone.ID
    ) -> [CKSyncEngine.PendingRecordZoneChange] {
        let validClipIDs = Set(
            clipUploadIDs.map { CKRecord.ID(recordName: $0.uuidString, zoneID: clipZoneID) })
        let validBoardIDs = Set(
            boardUploadIDs.map { CKRecord.ID(recordName: $0.uuidString, zoneID: boardZoneID) })

        return pendingChanges.filter { change in
            guard case .saveRecord(let id) = change else { return false }
            if id.zoneID.zoneName == clipZoneID.zoneName { return !validClipIDs.contains(id) }
            if id.zoneID.zoneName == boardZoneID.zoneName { return !validBoardIDs.contains(id) }
            return false
        }
    }

    /// An awaited work snapshot can predate a newly enqueued deletion. Automatic
    /// saves must preserve that newer intent; explicit user upload intents bypass
    /// this planner. Read the current queue and register this result without an
    /// intervening await. This adapter uses private zones, so a fetched owner and
    /// CloudKit's default-owner alias address the same zone and record name.
    static func retryChanges(
        _ changes: [CKSyncEngine.PendingRecordZoneChange],
        pendingChanges: [CKSyncEngine.PendingRecordZoneChange]
    ) -> [CKSyncEngine.PendingRecordZoneChange] {
        let deletions = Set(
            pendingChanges.compactMap { change -> RecordIdentity? in
                guard case .deleteRecord(let id) = change else { return nil }
                return RecordIdentity(id)
            })
        return changes.filter { change in
            guard case .saveRecord(let id) = change else { return true }
            return !deletions.contains(RecordIdentity(id))
        }
    }

    private struct RecordIdentity: Hashable, Sendable {
        let recordName: String
        let zoneName: String

        init(_ id: CKRecord.ID) {
            recordName = id.recordName
            zoneName = id.zoneID.zoneName
        }
    }
}

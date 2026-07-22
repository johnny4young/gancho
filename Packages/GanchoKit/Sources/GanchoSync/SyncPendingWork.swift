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
}

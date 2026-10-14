import CloudKit
import Foundation
import Testing

@testable import GanchoSync

@Suite("Sync pending-work planning")
struct SyncPendingWorkTests {
    private let clipZone = CKRecordZone.ID(
        zoneName: "clips", ownerName: CKCurrentUserDefaultName)
    private let boardZone = CKRecordZone.ID(
        zoneName: "boards", ownerName: CKCurrentUserDefaultName)

    @Test("Restart planning preserves work type, zone, and order")
    func plansEveryWorkType() {
        let clipUpload = UUID()
        let clipDeletion = UUID()
        let boardUpload = UUID()
        let boardDeletion = UUID()
        let work = SyncPendingWork(
            clipUploadIDs: [clipUpload],
            clipDeletionRecordNames: [clipDeletion.uuidString, "invalid"],
            boardUploadIDs: [boardUpload],
            boardDeletionRecordNames: [boardDeletion.uuidString, "invalid"])

        let changes = work.changes(clipZoneID: clipZone, boardZoneID: boardZone)

        #expect(changes.count == 4)
        expect(changes[0], is: .save, id: clipUpload, zone: clipZone)
        expect(changes[1], is: .delete, id: clipDeletion, zone: clipZone)
        expect(changes[2], is: .save, id: boardUpload, zone: boardZone)
        expect(changes[3], is: .delete, id: boardDeletion, zone: boardZone)
    }

    @Test("Reconciliation removes only stale saves in owned zones")
    func identifiesOnlyOwnedStaleSaves() {
        let validClip = UUID()
        let staleClip = UUID()
        let validBoard = UUID()
        let staleBoard = UUID()
        let foreignZone = CKRecordZone.ID(zoneName: "foreign", ownerName: CKCurrentUserDefaultName)
        let deletion = CKSyncEngine.PendingRecordZoneChange.deleteRecord(
            CKRecord.ID(recordName: staleClip.uuidString, zoneID: clipZone))
        let pending = [
            save(validClip, in: clipZone),
            save(staleClip, in: clipZone),
            save(validBoard, in: boardZone),
            save(staleBoard, in: boardZone),
            save(UUID(), in: foreignZone),
            deletion
        ]
        let work = SyncPendingWork(
            clipUploadIDs: [validClip], boardUploadIDs: [validBoard])

        let stale = work.staleSaveChanges(
            in: pending, clipZoneID: clipZone, boardZoneID: boardZone)

        #expect(stale == [save(staleClip, in: clipZone), save(staleBoard, in: boardZone)])
    }

    @Test("An automatic retry preserves a newer clip or board deletion", arguments: [false, true])
    func retryPreservesPendingDeletion(board: Bool) {
        let zone = board ? boardZone : clipZone
        let deletedID = CKRecord.ID(recordName: UUID().uuidString, zoneID: zone)
        let dirtyID = CKRecord.ID(recordName: UUID().uuidString, zoneID: zone)

        let retries = SyncPendingWork.retryChanges(
            [.saveRecord(deletedID), .saveRecord(dirtyID)],
            pendingChanges: [.deleteRecord(deletedID), .saveRecord(dirtyID)])

        #expect(retries == [.saveRecord(dirtyID)])
    }

    @Test("Ordinary clip and board saves still retry")
    func retryPreservesDirtySaves() {
        let clipID = CKRecord.ID(recordName: UUID().uuidString, zoneID: clipZone)
        let boardID = CKRecord.ID(recordName: UUID().uuidString, zoneID: boardZone)

        let retries = SyncPendingWork.retryChanges(
            [.saveRecord(clipID), .saveRecord(boardID)], pendingChanges: [])

        #expect(retries.count == 2)
        #expect(retries.contains(.saveRecord(clipID)))
        #expect(retries.contains(.saveRecord(boardID)))
    }

    @Test("A deletion in another zone does not block a save retry")
    func retryIgnoresUnrelatedZoneDeletion() {
        let name = UUID().uuidString
        let clipID = CKRecord.ID(recordName: name, zoneID: clipZone)
        let boardID = CKRecord.ID(recordName: name, zoneID: boardZone)

        let retries = SyncPendingWork.retryChanges(
            [.saveRecord(clipID)], pendingChanges: [.deleteRecord(boardID)])

        #expect(retries == [.saveRecord(clipID)])
    }

    @Test("A retry respects a deletion whose zone owner uses CloudKit's local alias")
    func retryMatchesOwnerAlias() {
        let name = UUID().uuidString
        let fetchedZone = CKRecordZone.ID(zoneName: clipZone.zoneName, ownerName: "synthetic-owner")
        let fetchedID = CKRecord.ID(recordName: name, zoneID: fetchedZone)
        let localID = CKRecord.ID(recordName: name, zoneID: clipZone)

        let retries = SyncPendingWork.retryChanges(
            [.saveRecord(fetchedID)], pendingChanges: [.deleteRecord(localID)])

        #expect(retries.isEmpty)
    }

    @Test("Restart retries retain their durable deletion changes")
    func retryRetainsSnapshotDeletion() {
        let clipID = CKRecord.ID(recordName: UUID().uuidString, zoneID: clipZone)
        let boardID = CKRecord.ID(recordName: UUID().uuidString, zoneID: boardZone)

        let retries = SyncPendingWork.retryChanges(
            [.deleteRecord(clipID), .saveRecord(boardID)],
            pendingChanges: [.saveRecord(clipID), .deleteRecord(boardID)])

        #expect(retries == [.deleteRecord(clipID)])
    }

    private enum ChangeKind { case save, delete }

    private func save(
        _ id: UUID, in zone: CKRecordZone.ID
    )
        -> CKSyncEngine.PendingRecordZoneChange
    {
        .saveRecord(CKRecord.ID(recordName: id.uuidString, zoneID: zone))
    }

    private func expect(
        _ change: CKSyncEngine.PendingRecordZoneChange,
        is kind: ChangeKind,
        id: UUID,
        zone: CKRecordZone.ID
    ) {
        switch (kind, change) {
        case (.save, .saveRecord(let recordID)), (.delete, .deleteRecord(let recordID)):
            #expect(recordID.recordName == id.uuidString)
            #expect(recordID.zoneID == zone)
        default:
            Issue.record("Unexpected pending change kind")
        }
    }
}

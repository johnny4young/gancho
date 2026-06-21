import CloudKit
import Foundation
import GanchoKit

/// Translates between a board (`Pinboard`) and a `CKRecord`, so the same
/// collections appear on every device — and, later, can be shared via a
/// `CKShare` on the board's zone. A board has no clipboard content, so only
/// metadata travels; the user-authored name still rides `encryptedValues`
/// because a board may be named after sensitive context (e.g. "Bank logins").
/// Membership (which clips belong to a board) lives on the clip record
/// (`ClipRecordMapper`), not here.
public enum BoardRecordMapper {
    public static let recordType = "Board"
    public static let zoneName = "BoardsZone"

    public static func record(
        for board: Pinboard, systemFields: Data?, zoneID: CKRecordZone.ID
    ) -> CKRecord? {
        let record: CKRecord
        if let systemFields {
            guard let unarchived = decodeSystemFields(systemFields) else { return nil }
            record = unarchived
        } else {
            let id = CKRecord.ID(recordName: board.id.uuidString, zoneID: zoneID)
            record = CKRecord(recordType: recordType, recordID: id)
        }
        record.encryptedValues["name"] = board.name
        record["sfSymbol"] = board.sfSymbol
        record["sortIndex"] = board.sortIndex
        record["isSystem"] = board.isSystem ? 1 : 0
        record["createdAt"] = board.createdAt
        return record
    }

    public static func decode(_ record: CKRecord) -> Pinboard? {
        guard let id = UUID(uuidString: record.recordID.recordName) else { return nil }
        return Pinboard(
            id: id,
            name: record.encryptedValues["name"] as? String ?? "",
            sfSymbol: record["sfSymbol"] as? String ?? "square.stack",
            sortIndex: record["sortIndex"] as? Int ?? 0,
            createdAt: record["createdAt"] as? Date ?? .now,
            isSystem: (record["isSystem"] as? Int ?? 0) == 1)
    }

    public static func encodeSystemFields(_ record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        return coder.encodedData
    }

    private static func decodeSystemFields(_ data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        let record = CKRecord(coder: coder)
        coder.finishDecoding()
        return record
    }
}

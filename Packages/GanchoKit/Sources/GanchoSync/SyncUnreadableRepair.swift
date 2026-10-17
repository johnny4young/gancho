import CloudKit
import Foundation

/// Restores synced clips this device's key cannot open by fetching their server
/// copy again: applying a record rewrites its blob under the current key, and
/// the change token never re-delivers an unchanged record on its own.
struct SyncUnreadableRepair: Sendable {
    struct Outcome: Sendable, Equatable {
        var restored = 0
        var remaining = 0
    }

    static let fetchChunkSize = 200

    let zoneID: CKRecordZone.ID
    let unreadable: @Sendable () async throws -> [UUID]
    let fetch: @Sendable ([CKRecord.ID]) async throws -> [CKRecord.ID: Result<CKRecord, any Error>]
    let apply: @Sendable ([CKRecord]) async throws -> Void

    /// Nil when nothing was unreadable. A record the server no longer has, or
    /// one without its payload, stays in `remaining`.
    func run() async throws -> Outcome? {
        let ids = try await unreadable()
        guard !ids.isEmpty else { return nil }
        let recordIDs = ids.map { CKRecord.ID(recordName: $0.uuidString, zoneID: zoneID) }
        for start in stride(from: 0, to: recordIDs.count, by: Self.fetchChunkSize) {
            try Task.checkCancellation()
            let chunk = Array(recordIDs[start..<min(start + Self.fetchChunkSize, recordIDs.count)])
            let records = try await fetch(chunk).values.compactMap { try? $0.get() }
            if !records.isEmpty { try await apply(records) }
        }
        let remaining = Set(try await unreadable())
        return Outcome(
            restored: Set(ids).subtracting(remaining).count, remaining: remaining.count)
    }
}

import CloudKit
import Foundation

/// A page is acknowledged only after every record and local write succeeds.
/// The returned checkpoint covers the whole cycle; partial durable upserts are
/// deliberately replayed through LWW after any later page fails.
struct SyncPullDriver: Sendable {
    struct DatabasePage: Sendable {
        var changedZones: Set<String>
        var deletedZones: Set<String> = []
        var token: Data
        var moreComing = false
    }

    struct ZonePage: Sendable {
        var records: [Result<CKRecord, any Error>]
        var deletions: [CKRecord.ID] = []
        var token: Data
        var moreComing = false
    }

    let databasePage: @Sendable (Data?) async throws -> DatabasePage
    let zonePage: @Sendable (String, Data?) async throws -> ZonePage
    let apply: @Sendable ([CKRecord], [CKRecord.ID]) async throws -> Void
    let resetZones: @Sendable (Set<String>) async throws -> Void
    /// Count of records a page could never deliver, reported content-free.
    var skipped: @Sendable (Int) async -> Void = { _ in }

    func pull(from checkpoint: SyncPollTokens, zones: [String]) async throws -> SyncPollTokens {
        var candidate = checkpoint
        var changed: Set<String> = []
        var resetDatabase = false
        while true {
            try Task.checkCancellation()
            do {
                let page = try await databasePage(candidate.database)
                try Task.checkCancellation()
                let deleted = page.deletedZones.intersection(zones)
                if !deleted.isEmpty { try await resetZones(deleted) }
                changed.formUnion(page.changedZones)
                for zone in page.deletedZones { candidate.zones[zone] = nil }
                if page.moreComing, page.token == candidate.database {
                    throw SyncReceiveFailure.nonAdvancingPage
                }
                candidate.database = page.token
                if !page.moreComing { break }
            } catch let error as CKError where error.code == .changeTokenExpired && !resetDatabase {
                // Recover now, once. Returning after a reset would let the
                // caller claim up-to-date without checking the server again.
                candidate = SyncPollTokens()
                changed = []
                resetDatabase = true
            }
        }
        for zone in zones where changed.contains(zone) {
            do {
                candidate.zones[zone] = try await pullZone(zone, since: candidate.zones[zone])
            } catch {
                guard CloudKitSyncPolicy.isMissingZone(error) else { throw error }
                try Task.checkCancellation()
                try await resetZones([zone])
                candidate.zones[zone] = nil
            }
        }
        try Task.checkCancellation()
        return candidate
    }

    private func pullZone(_ zone: String, since checkpoint: Data?) async throws -> Data {
        var token = checkpoint
        var reset = false
        while true {
            try Task.checkCancellation()
            do {
                let page = try await zonePage(zone, token)
                // A transient per-record error retains the checkpoint; a record
                // the server will never deliver is skipped rather than wedging.
                var records: [CKRecord] = []
                var permanentFailures = 0
                for result in page.records {
                    switch result {
                    case .success(let record): records.append(record)
                    case .failure(let error):
                        guard Self.isPermanentRecordFailure(error) else { throw error }
                        permanentFailures += 1
                    }
                }
                try Task.checkCancellation()
                try await apply(records, page.deletions)
                if permanentFailures > 0 { await skipped(permanentFailures) }
                try Task.checkCancellation()
                if page.moreComing, page.token == token {
                    throw SyncReceiveFailure.nonAdvancingPage
                }
                token = page.token
                if !page.moreComing { return page.token }
            } catch let error as CKError where error.code == .changeTokenExpired && !reset {
                token = nil
                reset = true
            }
        }
    }
}

extension SyncPullDriver {
    static func isPermanentRecordFailure(_ error: any Error) -> Bool {
        guard let error = error as? CKError else { return false }
        switch error.code {
        case .unknownItem, .assetFileNotFound, .assetFileModified, .invalidArguments: return true
        default: return false
        }
    }
}

/// Content-free failures with distinct retry policy: a broken checkpoint needs
/// an explicit retry after remediation, not an automatic hot loop.
enum SyncReceiveFailure: Error, Equatable {
    case apply(Int)
    case checkpointEncoding
    case nonAdvancingPage
    case interruptedByNewFailure
}

import CloudKit
import GanchoKit

/// Pure classification for CloudKit failures. Keeping policy out of the live
/// adapter makes every recovery branch deterministic and testable without an
/// account, container, or network connection.
enum CloudKitSyncPolicy {
    enum FailedSaveRecovery: Equatable, Sendable {
        case resolveConflict
        case recreateZone
        case pauseForQuota
        case deferToEngine
    }

    static func isMissingZone(_ error: Error) -> Bool {
        guard let ckError = error as? CKError else { return false }
        switch ckError.code {
        case .zoneNotFound, .userDeletedZone:
            return true
        case .partialFailure:
            guard let partial = ckError.partialErrorsByItemID?.values, !partial.isEmpty else {
                return false
            }
            return partial.allSatisfy { error in
                guard let child = error as? CKError else { return false }
                return child.code == .zoneNotFound || child.code == .userDeletedZone
            }
        default:
            return false
        }
    }

    static func interruption(for error: Error) -> SyncInterruption {
        guard let ckError = error as? CKError else { return .unknown }
        switch ckError.code {
        case .notAuthenticated: return .notSignedIn
        case .networkUnavailable, .networkFailure: return .offline
        case .quotaExceeded: return .iCloudFull
        default: return .unknown
        }
    }

    static func failedSaveRecovery(for code: CKError.Code) -> FailedSaveRecovery {
        switch code {
        case .serverRecordChanged: return .resolveConflict
        case .zoneNotFound, .userDeletedZone: return .recreateZone
        case .quotaExceeded: return .pauseForQuota
        default: return .deferToEngine
        }
    }
}

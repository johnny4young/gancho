import CloudKit
import Foundation
import GanchoKit

/// A successful older poll cannot clear a newer push-delivery failure.
struct SyncReceiveHealth: Sendable {
    private(set) var revision = 0
    private(set) var failure: SyncInterruption?

    mutating func fail(_ error: any Error) {
        revision += 1
        failure = CloudKitSyncPolicy.interruption(for: error)
    }

    mutating func recover(since snapshot: Int) -> Bool {
        guard revision == snapshot else { return false }
        failure = nil
        return true
    }
}

enum SyncReceiveRecovery {
    static func shouldRetry(_ error: any Error) -> Bool {
        if error is CancellationError { return false }
        if let failure = error as? SyncReceiveFailure {
            switch failure {
            case .checkpointEncoding, .nonAdvancingPage: return false
            case .apply, .interruptedByNewFailure: return true
            }
        }
        if let error = error as? CKError {
            switch error.code {
            case .notAuthenticated, .quotaExceeded, .permissionFailure, .missingEntitlement:
                return false
            default: return true
            }
        }
        return true
    }

    /// One bounded recovery cycle. Only a new explicit sync or a new receive
    /// event can start another cycle after exhaustion. Never logs raw errors.
    static func run(
        after initialError: any Error,
        sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        attempt: @Sendable () async throws -> Void
    ) async -> Bool {
        var failure = initialError
        for delay in [Duration.seconds(2), .seconds(5), .seconds(15)] {
            guard shouldRetry(failure), !Task.isCancelled else { return false }
            do {
                let retryAfter = (failure as? CKError)?.retryAfterSeconds ?? 0
                let wait =
                    retryAfter.isFinite && retryAfter > 0
                    ? max(delay, .seconds(retryAfter)) : delay
                try await sleep(wait)
                try Task.checkCancellation()
                try await attempt()
                return true
            } catch { failure = error }
        }
        return false
    }
}

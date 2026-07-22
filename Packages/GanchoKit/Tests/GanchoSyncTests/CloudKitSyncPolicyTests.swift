import CloudKit
import GanchoKit
import Testing

@testable import GanchoSync

@Suite("CloudKit sync policy")
struct CloudKitSyncPolicyTests {
    @Test(
        "User-facing interruptions stay structured",
        arguments: [
            (CKError.Code.notAuthenticated, SyncInterruption.notSignedIn),
            (.networkUnavailable, .offline),
            (.networkFailure, .offline),
            (.quotaExceeded, .iCloudFull),
            (.serverRejectedRequest, .unknown)
        ])
    func interruptions(code: CKError.Code, expected: SyncInterruption) {
        #expect(CloudKitSyncPolicy.interruption(for: error(code)) == expected)
    }

    @Test("Non-CloudKit failures do not leak implementation detail")
    func unknownInterruption() {
        #expect(CloudKitSyncPolicy.interruption(for: TestFailure()) == .unknown)
    }

    @Test(
        "Failed saves choose one explicit recovery",
        arguments: [
            (
                CKError.Code.serverRecordChanged,
                CloudKitSyncPolicy.FailedSaveRecovery.resolveConflict
            ),
            (.zoneNotFound, .recreateZone),
            (.userDeletedZone, .recreateZone),
            (.quotaExceeded, .pauseForQuota),
            (.networkFailure, .deferToEngine),
            (.requestRateLimited, .deferToEngine)
        ])
    func failedSaveRecovery(
        code: CKError.Code,
        expected: CloudKitSyncPolicy.FailedSaveRecovery
    ) {
        #expect(CloudKitSyncPolicy.failedSaveRecovery(for: code) == expected)
    }

    @Test("An empty partial failure is not mistaken for a missing zone")
    func emptyPartialFailure() {
        let partial = error(.partialFailure, userInfo: [CKPartialErrorsByItemIDKey: [:]])
        #expect(!CloudKitSyncPolicy.isMissingZone(partial))
    }

    @Test("A non-CloudKit partial child prevents missing-zone classification")
    func foreignPartialFailure() {
        let partial = error(
            .partialFailure,
            userInfo: [
                CKPartialErrorsByItemIDKey: [
                    "zone": error(.zoneNotFound),
                    "foreign": TestFailure()
                ]
            ])
        #expect(!CloudKitSyncPolicy.isMissingZone(partial))
    }

    private func error(_ code: CKError.Code, userInfo: [String: Any] = [:]) -> Error {
        NSError(domain: CKError.errorDomain, code: code.rawValue, userInfo: userInfo)
    }

    private struct TestFailure: Error {}
}

import CloudKit
import Foundation
import Testing

@testable import GanchoSync

private actor ReceiveAttempt {
    private var remainingFailures: Int
    private(set) var attempts = 0
    private(set) var delays: [Duration] = []
    init(failures: Int) { remainingFailures = failures }
    func sleep(_ delay: Duration) { delays.append(delay) }
    func attempt() throws {
        attempts += 1
        if remainingFailures > 0 {
            remainingFailures -= 1
            throw SyncReceiveFailure.apply(1)
        }
    }
}

@Suite("Sync receive — bounded recovery and health generations")
struct SyncReceiveRecoveryTests {
    @Test("An older successful pull never hides a newer receive error")
    func newerFailureSurvives() {
        var health = SyncReceiveHealth()
        health.fail(SyncReceiveFailure.apply(1))
        let old = health.revision
        health.fail(SyncReceiveFailure.undecodable(1))
        let clearedOld = health.recover(since: old)
        #expect(!clearedOld)
        #expect(health.failure != nil)
        let clearedCurrent = health.recover(since: health.revision)
        #expect(clearedCurrent)
        #expect(health.failure == nil)
    }

    @Test("Transient recovery stops on success and backs off without real sleeps")
    func transientRecovery() async {
        let scripted = ReceiveAttempt(failures: 1)
        let recovered = await SyncReceiveRecovery.run(
            after: SyncReceiveFailure.apply(1),
            sleep: { await scripted.sleep($0) }, attempt: { try await scripted.attempt() })
        #expect(recovered)
        #expect(await scripted.attempts == 2)
        #expect(await scripted.delays == [.seconds(2), .seconds(5)])
    }

    @Test("CloudKit retry-after is a minimum, not ignored by local backoff")
    func serverRetryAfter() async {
        let scripted = ReceiveAttempt(failures: 0)
        let error = NSError(
            domain: CKError.errorDomain, code: CKError.requestRateLimited.rawValue,
            userInfo: [CKErrorRetryAfterKey: 60.0])
        #expect(
            await SyncReceiveRecovery.run(
                after: error,
                sleep: { await scripted.sleep($0) }, attempt: { try await scripted.attempt() }))
        #expect(await scripted.delays == [.seconds(60)])
    }

    @Test("Retries are capped at three attempts")
    func exhausted() async {
        let scripted = ReceiveAttempt(failures: 9)
        #expect(
            await SyncReceiveRecovery.run(
                after: CKError(.networkFailure),
                sleep: { await scripted.sleep($0) }, attempt: { try await scripted.attempt() })
                == false)
        #expect(await scripted.attempts == 3)
        #expect(await scripted.delays == [.seconds(2), .seconds(5), .seconds(15)])
    }

    @Test("Malformed data, account gates and cancellation do not start a hot loop")
    func permanentFailure() async {
        let errors: [any Error] = [
            SyncReceiveFailure.undecodable(1), SyncReceiveFailure.checkpointEncoding,
            CKError(.notAuthenticated), CKError(.quotaExceeded), CancellationError()
        ]
        for error in errors {
            let recovered = await SyncReceiveRecovery.run(
                after: error,
                sleep: { _ in Issue.record("must not sleep") },
                attempt: { Issue.record("must not retry") })
            #expect(!recovered)
        }
    }

    @Test("Cancellation during the wait prevents the next attempt")
    func cancellationDuringWait() async {
        let task = Task {
            await SyncReceiveRecovery.run(
                after: SyncReceiveFailure.apply(1),
                sleep: { _ in withUnsafeCurrentTask { $0?.cancel() } },
                attempt: { Issue.record("cancelled attempt must not run") })
        }
        #expect(await task.value == false)
    }
}

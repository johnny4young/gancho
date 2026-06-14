import ClipboardCore
import Foundation
import GanchoKit
import Testing

@Suite("Sync activity log — metadata only, newest first")
struct SyncActivityLogTests {
    @Test("Recent sync events come back newest-first and limited")
    func recentNewestFirst() {
        let recorder = InMemoryPrivacyEventRecorder()
        let base = Date(timeIntervalSince1970: 1_000)
        recorder.record(sync: SyncActivityEvent(kind: .synced, occurredAt: base))
        recorder.record(
            sync: SyncActivityEvent(
                kind: .paused, cause: .iCloudFull, occurredAt: base.addingTimeInterval(10)))
        recorder.record(
            sync: SyncActivityEvent(
                kind: .failed, cause: .offline, occurredAt: base.addingTimeInterval(20)))

        let recent = recorder.recentSyncEvents(limit: 2)
        #expect(recent.count == 2)
        #expect(recent.first?.kind == .failed)  // newest first
        #expect(recent.first?.cause == .offline)
        #expect(recent.last?.kind == .paused)
        #expect(recent.last?.cause == .iCloudFull)
    }

    @Test("A clean sync carries no cause; an interruption does — and round-trips")
    func causeRoundTrips() throws {
        let clean = SyncActivityEvent(kind: .synced)
        #expect(clean.cause == nil)

        let interrupted = SyncActivityEvent(kind: .paused, cause: .iCloudFull)
        let decoded = try JSONDecoder().decode(
            SyncActivityEvent.self, from: JSONEncoder().encode(interrupted))
        #expect(decoded == interrupted)
        #expect(decoded.cause == .iCloudFull)
    }
}

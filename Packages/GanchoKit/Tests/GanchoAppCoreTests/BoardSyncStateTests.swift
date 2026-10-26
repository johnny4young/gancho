import Foundation
import Testing

@testable import GanchoAppCore

@Suite("Board sync state — what a board row says about iCloud")
struct BoardSyncStateTests {
    @Test("Off means on this device; on, a pending change waits, the rest is synced")
    func states() {
        let board = UUID()
        #expect(
            BoardSyncState(boardID: board, syncEnabled: false, awaitingUpload: [board])
                == .onThisDevice)
        #expect(
            BoardSyncState(boardID: board, syncEnabled: true, awaitingUpload: [board]) == .waiting)
        #expect(
            BoardSyncState(boardID: board, syncEnabled: true, awaitingUpload: [UUID()]) == .synced)
        #expect(
            BoardSyncState(
                boardID: board, syncEnabled: true, syncHealthy: false, awaitingUpload: [])
                == .waiting, "a paused or failing sync never reads as synced")
    }
}

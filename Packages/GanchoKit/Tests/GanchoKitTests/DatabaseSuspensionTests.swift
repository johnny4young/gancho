import Foundation
import GRDB
import Testing

@testable import GanchoKit

/// The seam just bridges to GRDB's notifications; the actual lock-release
/// behavior remains a physical-device qualification gate. Here we prove the
/// notification seam and restore lifecycle state after every test.
@Suite("DatabaseSuspension — GRDB notification seam", .serialized)
struct DatabaseSuspensionTests {
    @Test("suspend() posts GRDB's suspend notification")
    func suspendPostsNotification() async {
        defer { DatabaseSuspension.resume() }
        await confirmation { confirmed in
            let token = NotificationCenter.default.addObserver(
                forName: Database.suspendNotification, object: nil, queue: nil
            ) { _ in confirmed() }
            defer { NotificationCenter.default.removeObserver(token) }
            DatabaseSuspension.suspend()
        }
    }

    @Test("resume() posts GRDB's resume notification")
    func resumePostsNotification() async {
        await confirmation { confirmed in
            let token = NotificationCenter.default.addObserver(
                forName: Database.resumeNotification, object: nil, queue: nil
            ) { _ in confirmed() }
            defer { NotificationCenter.default.removeObserver(token) }
            DatabaseSuspension.resume()
        }
    }
}

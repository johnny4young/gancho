import Foundation
import GRDB
import Testing

@testable import GanchoKit

/// The seam just bridges to GRDB's notifications; the actual lock-release
/// behavior is GRDB's, verified on device. Here we prove we post the right ones.
@Suite("DatabaseSuspension — GRDB notification seam")
struct DatabaseSuspensionTests {
    @Test("suspend() posts GRDB's suspend notification")
    func suspendPostsNotification() async {
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

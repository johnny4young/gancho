import GanchoAppCore
import GanchoKit
import UIKit

/// Runs the retention purge on the way to the background, then releases the
/// store's SQLite locks.
///
/// The ordering is the whole point. `DatabaseSuspension.suspend()` must happen
/// before iOS suspends the process or the app is killed with 0xDEAD10CC, so it
/// cannot simply be moved after an `await`. A background-task assertion buys
/// the seconds the purge needs, and the suspend runs on BOTH exits: when the
/// purge finishes, and when iOS takes the time back first. Whichever comes
/// first wins; the other becomes a no-op.
///
/// The purge can also outlive the transition that started it. If the user comes
/// back while it is still running, the foreground has already resumed the store
/// and this must not suspend it again underneath a live screen — so both exits
/// route through `StoreSuspension`, which grants the suspend only to the newest
/// window and only while the app is off screen.
///
/// Why purge here at all, when `RetentionBackgroundTask` also covers it:
/// leaving the app is the moment the clock on an expired secret starts
/// mattering, and BGAppRefresh may not be granted for hours.
@MainActor
enum BackgroundPurge {
    /// Tracks the assertion so both exits release it exactly once.
    private final class Assertion {
        var identifier: UIBackgroundTaskIdentifier = .invalid
        var finished = false
    }

    static func run(model: IOSAppModel) {
        let assertion = Assertion()
        let application = UIApplication.shared
        let token = StoreSuspension.beginBackgroundWindow()
        assertion.identifier = application.beginBackgroundTask(withName: "gancho-retention") {
            // Out of time. Release the locks immediately — a killed process is
            // worse than a skipped purge.
            MainActor.assumeIsolated {
                finish(assertion, application: application, token: token)
            }
        }
        // No assertion granted (rare, but possible): fall back to the exact
        // behavior this replaced rather than risking a delayed suspend.
        guard assertion.identifier != .invalid else {
            StoreSuspension.suspendWithoutWindow()
            return
        }
        Task {
            await model.runMaintenance(refreshingList: false, ignoringThrottle: true)
            finish(assertion, application: application, token: token)
        }
    }

    private static func finish(
        _ assertion: Assertion,
        application: UIApplication,
        token: BackgroundWorkWindows.Token
    ) {
        guard !assertion.finished else { return }
        assertion.finished = true
        StoreSuspension.endWindow(token)
        if assertion.identifier != .invalid {
            application.endBackgroundTask(assertion.identifier)
            assertion.identifier = .invalid
        }
    }
}

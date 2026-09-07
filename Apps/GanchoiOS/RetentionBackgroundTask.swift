import BackgroundTasks
import Foundation
import GanchoKit

/// Runs the retention purge on a phone the user has not opened.
///
/// macOS purges every five minutes on a timer; iOS had no equivalent — the
/// purge ran only when the app came to the foreground, throttled to once every
/// ten minutes. A clip flagged sensitive therefore survived for as long as the
/// user did not open Gancho, which is exactly the device most likely to be lost
/// with a secret still in it. `docs/SECURITY-MODEL.md` claims those items
/// expire in minutes; on iOS that was only true for an app in active use.
///
/// This never captures. The registered work deletes expired rows and nothing
/// else, which is why the `fetch` background mode it needs does not weaken the
/// "no silent iOS capture" invariant.
///
/// BGAppRefresh is opportunistic by design: iOS decides when, based on usage,
/// battery, and network. It shortens the worst case; it does not make expiry a
/// guarantee, and the security model says so.
@MainActor
enum RetentionBackgroundTask {
    /// Must match `BGTaskSchedulerPermittedIdentifiers` in the Info.plist.
    static let identifier = "com.johnny4young.gancho.retention"

    /// Roughly an hour out. iOS treats this as "no earlier than", not a
    /// promise, and will space runs further apart on its own.
    private static let earliestInterval: TimeInterval = 60 * 60

    /// Registers the handler. Must run before the app finishes launching, or
    /// `BGTaskScheduler` raises.
    static func register(model: @escaping @MainActor () -> IOSAppModel?) {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: identifier, using: nil
        ) { task in
            MainActor.assumeIsolated {
                handle(task, model: model())
            }
        }
    }

    /// Asks for the next run. Safe to call repeatedly: a resubmission replaces
    /// the pending request rather than queueing another.
    static func schedule() {
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: earliestInterval)
        // Throws when the identifier is not permitted or the app is not
        // entitled — neither is recoverable at runtime, and neither should
        // take down a launch.
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handle(_ task: BGTask, model: IOSAppModel?) {
        // Chain the next request FIRST: if the purge or the OS cuts this run
        // short, a successor is already queued rather than the chain ending
        // silently here.
        schedule()
        guard let model else {
            task.setTaskCompleted(success: false)
            return
        }
        let work = Task { @MainActor in
            // No list to refresh with the app in the background, and the
            // ten-minute foreground throttle must not skip a run the OS granted
            // hours later.
            await model.runMaintenance(refreshingList: false, ignoringThrottle: true)
            task.setTaskCompleted(success: true)
        }
        task.expirationHandler = { work.cancel() }
    }
}

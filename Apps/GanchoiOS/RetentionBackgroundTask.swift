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
/// This never captures — the pasteboard is not read on this path at all, which
/// is why the `fetch` background mode it needs does not weaken the "no silent
/// iOS capture" invariant. It is not purge-only, though: it runs the same
/// `runMaintenance` the foreground does, which deletes expired rows, records
/// the content-free expiry count, enqueues CloudKit tombstones for the rows it
/// just removed, and applies tier enforcement (archiving or releasing rows when
/// the entitlement changed). All of that is metadata and row lifecycle; none of
/// it reads or captures content.
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
    ///
    /// `using:` is the queue the launch handler runs on. `nil` means an
    /// unspecified BACKGROUND queue, where `MainActor.assumeIsolated` is a
    /// precondition failure — it would trap the moment iOS granted a refresh.
    /// `.main` is what makes the assumption true; the handler only schedules
    /// and hands off, so it never blocks that queue.
    static func register(model: @escaping @MainActor () -> IOSAppModel?) {
        BGTaskScheduler.shared.register(
            forTaskWithIdentifier: identifier, using: .main
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
        // This process may have been backgrounded for hours, with the store
        // suspended since `BackgroundPurge` finished and no `.active`
        // transition in between. GRDB refuses writes on a suspended pool, so
        // without this the purge would run and delete nothing.
        let token = StoreSuspension.beginBackgroundWindow()
        StoreSuspension.resumeForBackgroundWork()
        let work = Task { @MainActor in
            // No list to refresh with the app in the background, and the
            // ten-minute foreground throttle must not skip a run the OS granted
            // hours later.
            await model.runMaintenance(refreshingList: false, ignoringThrottle: true)
            // Back to where we found it: still backgrounded means still
            // suspended, or the next process suspension is a 0xDEAD10CC. This
            // runs on both exits because expiration only cancels, leaving the
            // completion path below to do the cleanup exactly once.
            StoreSuspension.endWindow(token)
            task.setTaskCompleted(success: !Task.isCancelled)
        }
        // Cancel only. Unlike `beginBackgroundTask`, whose expiration handler
        // UIKit documents as running on the main thread, `BGTask` does not
        // promise a queue here — so this must not assume main-actor isolation
        // either. Cancelling is safe from anywhere, and the task body above
        // still reaches its cleanup.
        task.expirationHandler = { work.cancel() }
    }
}

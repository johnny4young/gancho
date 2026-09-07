import GanchoAppCore
import GanchoKit
import UIKit

/// Decides when background work is allowed to release the store's SQLite locks.
///
/// `DatabaseSuspension` is the mechanism; this is the policy. Suspension is
/// correct only when the app is really on its way out, and background work
/// routinely outlives the transition that started it: a purge can finish after
/// the user has already come back, and a BGAppRefresh launch can arrive hours
/// after an earlier window suspended the store. Suspending in either case pulls
/// the locks out from under a live screen, or from under newer work.
///
/// `BackgroundWorkWindows` holds the ordering rule and is unit-tested in
/// `GanchoAppCoreTests`; this type supplies the two things it cannot know —
/// what UIKit says about the UI, and how to actually suspend.
@MainActor
enum StoreSuspension {
    private static var windows = BackgroundWorkWindows()

    /// Call on `.active`. Resumes the store and retires every window in flight,
    /// so nothing that started earlier can suspend under the foreground.
    static func appDidBecomeActive() {
        windows.activate()
        DatabaseSuspension.resume()
    }

    /// Opens a background work window. Hand the token to ``endWindow(_:)`` on
    /// every exit path, including the one where the OS reclaims the time.
    static func beginBackgroundWindow() -> BackgroundWorkWindows.Token {
        windows.beginWindow()
    }

    /// Resumes the store for a background window that may have inherited a
    /// suspended pool.
    ///
    /// A BGAppRefresh launch can wake an already-backgrounded process long
    /// after `BackgroundPurge` suspended the store, with no `.active`
    /// transition in between. GRDB refuses writes on a suspended pool, so the
    /// purge would run and delete nothing at all.
    static func resumeForBackgroundWork() {
        DatabaseSuspension.resume()
    }

    /// Suspends the store if this window is still the one that owns the
    /// decision and the app is not on screen. Otherwise a no-op.
    static func endWindow(_ token: BackgroundWorkWindows.Token) {
        let isActive = UIApplication.shared.applicationState == .active
        guard windows.shouldSuspend(token: token, isActive: isActive) else { return }
        DatabaseSuspension.suspend()
    }

    /// Unconditional suspend for the path that never opened a window: no
    /// background assertion was granted, so there is no time to purge and the
    /// 0xDEAD10CC guard has to run right now.
    static func suspendWithoutWindow() {
        DatabaseSuspension.suspend()
    }
}

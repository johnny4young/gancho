/// Ordering for background work that must release the store's SQLite locks
/// when it finishes — but only when releasing them is still the right thing.
///
/// iOS suspends the database on the way to the background (the 0xDEAD10CC
/// guard) and resumes it on return to the foreground. Two races follow from
/// work that outlives the transition that started it:
///
/// 1. Purge-on-background is still running when the user comes back. The
///    foreground resumes the store, then the finishing purge suspends it again
///    underneath a live UI.
/// 2. A BGAppRefresh launch hours later, or a rapid background → foreground →
///    background cycle, leaves an older run able to suspend a store a newer one
///    is still using.
///
/// Each window gets a token. Suspension is granted only to the newest window,
/// and only while the app is not active — so a stale finisher becomes a no-op
/// instead of pulling the locks out from under whatever is running now.
///
/// Deliberately pure: the platform decides what "active" means and how to
/// suspend, this only decides *whether*.
public struct BackgroundWorkWindows: Sendable, Equatable {
    /// A window's claim on the suspend. Only ``beginWindow()`` can mint one, so
    /// there is no "no window has started yet" value a caller could pass in and
    /// be granted a suspend with.
    public struct Token: Sendable, Equatable {
        fileprivate let value: Int
    }

    /// The newest window. Zero before any background work, which matches no
    /// token.
    private var current: Int = 0

    public init() {}

    /// Opens a window. The token comes back to
    /// ``shouldSuspend(token:isActive:)`` on every exit path.
    public mutating func beginWindow() -> Token {
        current += 1
        return Token(value: current)
    }

    /// Records a return to the foreground, invalidating every window in flight.
    public mutating func activate() {
        current += 1
    }

    /// Whether work holding `token` may suspend the store now.
    ///
    /// Both conditions matter. `isActive` is the ground truth about the UI: no
    /// amount of ordering makes it safe to suspend under a live screen. The
    /// token check handles the case where the app is still backgrounded but a
    /// newer window has already taken over — the newest window owns the
    /// suspend, so the older one must not run it early.
    public func shouldSuspend(token: Token, isActive: Bool) -> Bool {
        !isActive && token.value == current
    }
}

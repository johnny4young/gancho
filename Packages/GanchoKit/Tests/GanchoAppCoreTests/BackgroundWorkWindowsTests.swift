import Testing

@testable import GanchoAppCore

@Suite("BackgroundWorkWindows — who is allowed to suspend the store")
struct BackgroundWorkWindowsTests {
    @Test("The only window in flight suspends when the app is backgrounded")
    func loneWindowSuspends() {
        var windows = BackgroundWorkWindows()
        let token = windows.beginWindow()
        #expect(windows.shouldSuspend(token: token, isActive: false))
    }

    @Test("A window that finishes after the user returns never suspends")
    func foregroundReturnCancelsTheSuspend() {
        var windows = BackgroundWorkWindows()
        let token = windows.beginWindow()
        windows.activate()
        #expect(!windows.shouldSuspend(token: token, isActive: false))

        // A live UI is disqualifying on its own — the two guards are
        // independent, so even the current window may not suspend while active.
        var live = BackgroundWorkWindows()
        let currentToken = live.beginWindow()
        #expect(!live.shouldSuspend(token: currentToken, isActive: true))
    }

    @Test("Background, foreground, background: only the newest window suspends")
    func rapidCyclingLeavesOneOwner() {
        var windows = BackgroundWorkWindows()
        let first = windows.beginWindow()
        windows.activate()
        let second = windows.beginWindow()
        #expect(!windows.shouldSuspend(token: first, isActive: false))
        #expect(windows.shouldSuspend(token: second, isActive: false))
    }

    @Test("A later window supersedes an earlier one without a foreground in between")
    func newerBackgroundWindowSupersedes() {
        // Purge-on-background is still running when a BGAppRefresh launch opens
        // its own window; the refresh now owns the suspend.
        var windows = BackgroundWorkWindows()
        let purge = windows.beginWindow()
        let refresh = windows.beginWindow()
        #expect(!windows.shouldSuspend(token: purge, isActive: false))
        #expect(windows.shouldSuspend(token: refresh, isActive: false))
    }

    @Test("Every exit path of the newest window suspends exactly once per window")
    func newestWindowStaysAuthoritative() {
        // Both `BackgroundPurge` exits — the purge finishing and the OS
        // reclaiming the assertion — ask the same question with the same token,
        // and the answer must not change between them.
        var windows = BackgroundWorkWindows()
        let token = windows.beginWindow()
        #expect(windows.shouldSuspend(token: token, isActive: false))
        #expect(windows.shouldSuspend(token: token, isActive: false))
    }
}

import AppKit
import XCTest

/// Regression coverage for the reported "resident but iconless" trap: the
/// menu-bar helper dies (a crash, or a Quit that didn't fully take) and the
/// agent stays resident with no icon and no way back short of killing the
/// process. `applicationShouldHandleReopen` → `ensureMenuBarPresence()` must
/// re-establish a menu-bar affordance when the user clicks Gancho.app.
///
/// Needs the real (Apple Development-signed) helper, so it self-skips under the
/// CI ad-hoc signing exactly like the sibling menu-bar tests in `PanelUITests`.
final class MenuBarRecoveryUITests: XCTestCase {
    private let ganchoBundleID = "com.johnny4young.gancho"

    @MainActor
    func testReopenRestoresTheMenuBarAfterTheHelperDies() throws {
        if ProcessInfo.processInfo.environment["GANCHO_UI_ADHOC_SIGNING"] == "1" {
            throw XCTSkip(
                "menu-bar helper launch requires Apple Development signing; CI uses ad-hoc")
        }
        terminateMenuBarHelpers()
        let app = XCUIApplication()
        app.launch()
        defer {
            app.terminate()
            _ = waitForMenuBarHelpers(present: false, timeout: 5)
        }
        XCTAssertTrue(
            waitForMenuBarHelpers(present: true, timeout: 5),
            "launch must start the menu-bar helper")

        // Kill the helper out from under the resident agent.
        terminateMenuBarHelpers()
        guard waitForMenuBarHelpers(present: false, timeout: 5) else {
            throw XCTSkip("could not terminate the helper on this runner")
        }

        // Clicking Gancho.app re-opens the running instance (a reopen, not a new
        // launch). Resolve the running bundle's URL and open it; the agent must
        // bring the menu bar back instead of staying resident-but-iconless.
        guard
            let bundleURL =
                NSRunningApplication
                .runningApplications(withBundleIdentifier: ganchoBundleID)
                .first?.bundleURL
        else {
            throw XCTSkip("running Gancho bundle URL not resolvable on this runner")
        }
        NSWorkspace.shared.open(bundleURL)

        XCTAssertTrue(
            waitForMenuBarHelpers(present: true, timeout: 6),
            "reopen must revive the menu-bar icon, not leave the agent iconless")
    }

    // MARK: - Helper-process observation

    @MainActor
    private func menuBarHelpers() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { app in
            app.localizedName == "GanchoMenuBarHelper"
                || app.executableURL?.lastPathComponent == "GanchoMenuBarHelper"
        }
    }

    @MainActor
    private func terminateMenuBarHelpers() {
        for app in menuBarHelpers() { _ = app.terminate() }
        _ = waitForMenuBarHelpers(present: false, timeout: 2)
    }

    @MainActor
    private func waitForMenuBarHelpers(present: Bool, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if menuBarHelpers().isEmpty != present { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return menuBarHelpers().isEmpty != present
    }
}

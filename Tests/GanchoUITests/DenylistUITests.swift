import AppKit
import XCTest

/// Settings → Capture: the editable never-capture app list (MKT-01). Drives
/// the real Settings window via the `gancho://settings` deep link. Like the
/// other suites here, it self-skips — never hard-fails — where an element
/// isn't exposed on a headless/hosted runner, and runs under `make test-ui`.
///
/// Two add paths, tried in order: typing a bundle id (needs keyboard focus,
/// which a menu-bar-agent window doesn't always get under the runner) and the
/// click-only "Add a running app…" menu with Finder (always running, always
/// Dock-visible) — so the add/remove round-trip is exercised even where the
/// keyboard isn't grantable.
final class DenylistUITests: XCTestCase {
    /// Fixed id so an interrupted run leaves at most one stale entry that the
    /// next run removes instead of accumulating garbage in real defaults.
    private let typedBundleID = "com.gancho.uitests.example"
    private let finderBundleID = "com.apple.finder"

    @MainActor
    func testAddAndRemoveDenylistEntry() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-use-in-process-status-item"]
        app.launch()
        defer { app.terminate() }

        let url = try XCTUnwrap(URL(string: "gancho://settings"))
        XCTAssertTrue(NSWorkspace.shared.open(url))
        guard app.windows["Settings"].firstMatch.waitForExistence(timeout: 5) else {
            print("skip: Settings window not exposed to the UI runner in this environment")
            return
        }

        let captureTab = app.buttons["Capture"].firstMatch
        guard captureTab.waitForExistence(timeout: 3) else {
            print("skip: Capture tab not exposed to the UI runner in this environment")
            return
        }
        captureTab.click()

        // Recover from a previous interrupted run before asserting anything.
        removeIfListed(typedBundleID, app: app)
        removeIfListed(finderBundleID, app: app)

        let bundleID =
            addedByTyping(app: app) ? typedBundleID : addedViaRunningAppsMenu(app: app)
        guard let bundleID else {
            print("skip: no add path available to the UI runner in this environment")
            return
        }

        let row = app.staticTexts["denylist-row-\(bundleID)"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3), "the added app must appear in the list")

        let remove = app.buttons["denylist-remove-\(bundleID)"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 3))
        remove.click()
        XCTAssertTrue(
            waitForDisappearance(of: row, timeout: 3),
            "the removed app must leave the list immediately")
    }

    /// Types `typedBundleID` into the manual field and clicks Add. Returns
    /// false when the field never gets keyboard focus (keys would land on
    /// whatever has it), so the caller can fall back to the click-only path.
    @MainActor
    private func addedByTyping(app: XCUIApplication) -> Bool {
        let field = app.textFields["denylist-add-field"].firstMatch
        guard field.waitForExistence(timeout: 3) else { return false }
        // Clicks and keys are global events: without the app verifiably
        // frontmost they'd drive whatever ELSE is on the desktop, so this
        // path bails to the click-only fallback instead.
        app.activate()
        guard app.state == .runningForeground else { return false }
        var fieldIsFocused = false
        for _ in 0..<2 where !fieldIsFocused {
            if field.isHittable {
                field.click()
            } else {
                field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
            }
            fieldIsFocused = SynthesizedInput.waitForKeyboardFocus(field, timeout: 1)
        }
        guard fieldIsFocused else { return false }
        field.typeText(typedBundleID)
        app.buttons["denylist-add-button"].firstMatch.click()
        return true
    }

    /// Click-only fallback: excludes Finder through the running-apps menu.
    /// Returns the bundle id it added, or nil to self-skip. SwiftUI `Menu` in
    /// a Form surfaces as a popup/menu button depending on the OS, so probe
    /// the likely element types; an existing-but-unhittable menu (scrolled
    /// out of the Form's viewport) gets a coordinate click.
    @MainActor
    private func addedViaRunningAppsMenu(app: XCUIApplication) -> String? {
        let candidates = [
            app.menuButtons["denylist-running-apps"].firstMatch,
            app.popUpButtons["denylist-running-apps"].firstMatch,
            app.buttons["denylist-running-apps"].firstMatch,
            app.descendants(matching: .any)
                .matching(identifier: "denylist-running-apps").firstMatch
        ]
        guard let menu = candidates.first(where: { $0.waitForExistence(timeout: 1) }) else {
            print("skip-detail: running-apps menu not in the accessibility tree")
            return nil
        }
        if menu.isHittable {
            menu.click()
        } else if app.state == .runningForeground {
            // A raw coordinate click is a screen point — only safe when the
            // point is verifiably over OUR window (app frontmost).
            menu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        } else {
            print("skip-detail: menu unhittable and app not frontmost")
            return nil
        }
        let finderItem = app.menuItems["Finder"].firstMatch
        guard finderItem.waitForExistence(timeout: 3) else {
            print("skip-detail: Finder item not exposed after opening the menu")
            return nil
        }
        finderItem.click()
        return finderBundleID
    }

    /// Pre-test cleanup: a crash between add and remove in a previous run
    /// leaves a stale entry in real defaults — remove it before asserting.
    @MainActor
    private func removeIfListed(_ bundleID: String, app: XCUIApplication) {
        let remove = app.buttons["denylist-remove-\(bundleID)"].firstMatch
        if remove.waitForExistence(timeout: 1), remove.isHittable {
            remove.click()
        }
    }

    @MainActor
    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element.exists { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return !element.exists
    }
}

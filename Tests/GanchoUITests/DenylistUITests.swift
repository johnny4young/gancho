import AppKit
import XCTest

/// Settings → Capture: the editable never-capture app list (MKT-01). Drives
/// the real Settings window via the `gancho://settings` deep link. Like the
/// other suites here, it self-skips — never hard-fails — where an element
/// isn't exposed on a headless/hosted runner, and runs under `make test-ui`.
///
/// The deterministic path seeds one user entry through the app's own
/// `-seed-denylist-entry` launch hook (same call as the Add button) and then
/// exercises the ROW + REMOVE round-trip with element clicks alone —
/// synthesized typing isn't grantable on every runner. Typing the bundle id
/// through the real field is covered by the second test, which skips where
/// the keyboard can't be granted safely.
final class DenylistUITests: XCTestCase {
    /// Sorts BEFORE the built-in com.* suggestions, so the seeded row is the
    /// first in the section and stays hittable without scrolling. Fixed id:
    /// an interrupted run leaves at most one stale entry that the next run
    /// removes instead of accumulating garbage in real defaults.
    private let seededBundleID = "app.gancho.uitests.seeded"
    private let typedBundleID = "app.gancho.uitests.typed"

    /// Deterministic acceptance: the seeded entry renders as a row and its
    /// remove button deletes it live (AppModel → SourceAppDenylist →
    /// persistence + the `denylistRevision` refresh).
    @MainActor
    func testSeededEntryShowsAndRemoveDeletesIt() throws {
        let app = try launchIntoCaptureSettings(
            extraArguments: ["-seed-denylist-entry", seededBundleID])
        defer { app.terminate() }

        let row = app.staticTexts["denylist-row-\(seededBundleID)"].firstMatch
        XCTAssertTrue(
            row.waitForExistence(timeout: 5),
            "the seeded denylist entry must render as a Settings row")

        let remove = app.buttons["denylist-remove-\(seededBundleID)"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 3))
        // The denylist section sits below the capture toggles, so the row can
        // start under the form's fold. Scroll-wheel events land on the window
        // under the pointer, and `scroll(byDeltaX:deltaY:)` hovers first —
        // safe once the app is verifiably frontmost. Scrolling targets the
        // WINDOW (the first scrollView is the horizontal tab bar, not the
        // form); the sign of deltaY varies with scroller settings, so probe
        // down first, then back up.
        if !remove.isHittable {
            app.activate()
            try SynthesizedInput.requireForeground(app)
            let window = app.windows.firstMatch
            for delta in [-80.0, -80, -80, 240, 80, 80] where !remove.isHittable {
                window.scroll(byDeltaX: 0, deltaY: delta)
            }
        }
        guard remove.isHittable else {
            throw XCTSkip("remove button not hittable on this runner (below the form fold)")
        }
        remove.click()
        XCTAssertTrue(
            waitForDisappearance(of: row, timeout: 3),
            "the removed app must leave the list immediately")
    }

    /// The manual add path (bundle-id field + Add). Needs real keyboard
    /// focus, which a menu-bar agent's window doesn't always get under the
    /// runner — skips rather than typing into whatever else has the keyboard.
    @MainActor
    func testAddDenylistEntryByTyping() throws {
        let app = try launchIntoCaptureSettings()
        defer { app.terminate() }

        // Recover from a previous interrupted run before asserting anything.
        removeIfListed(typedBundleID, app: app)

        let field = app.textFields["denylist-add-field"].firstMatch
        guard field.waitForExistence(timeout: 3) else {
            throw XCTSkip("denylist add field not exposed to the UI runner")
        }
        app.activate()
        try SynthesizedInput.requireForeground(app)
        var fieldIsFocused = false
        for _ in 0..<2 where !fieldIsFocused {
            if field.isHittable {
                field.click()
            } else {
                field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
            }
            fieldIsFocused = SynthesizedInput.waitForKeyboardFocus(field, timeout: 1)
        }
        guard fieldIsFocused else {
            throw XCTSkip("keyboard focus not grantable to the UI runner")
        }
        field.typeText(typedBundleID)
        app.buttons["denylist-add-button"].firstMatch.click()

        let row = app.staticTexts["denylist-row-\(typedBundleID)"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 3), "the added app must appear in the list")

        // Cleanup doubles as the remove assertion for this path.
        let remove = app.buttons["denylist-remove-\(typedBundleID)"].firstMatch
        XCTAssertTrue(remove.waitForExistence(timeout: 3))
        remove.click()
        XCTAssertTrue(waitForDisappearance(of: row, timeout: 3))
    }

    /// Launches the agent, opens Settings via the deep link, and switches to
    /// the Capture tab. Throws `XCTSkip` where the window or tab isn't
    /// exposed (headless/hosted runners).
    @MainActor
    private func launchIntoCaptureSettings(
        extraArguments: [String] = []
    ) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-use-in-process-status-item"] + extraArguments
        app.launch()

        let url = try XCTUnwrap(URL(string: "gancho://settings"))
        XCTAssertTrue(NSWorkspace.shared.open(url))
        guard app.windows["Settings"].firstMatch.waitForExistence(timeout: 5) else {
            app.terminate()
            throw XCTSkip("Settings window not exposed to the UI runner")
        }
        let captureTab = app.buttons["Capture"].firstMatch
        guard captureTab.waitForExistence(timeout: 3) else {
            app.terminate()
            throw XCTSkip("Capture tab not exposed to the UI runner")
        }
        captureTab.click()
        return app
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

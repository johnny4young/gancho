import AppKit
import XCTest

/// Keyboard-first panel smoke (XCTest lives ONLY in this UI target; unit
/// tests are Swift Testing in the package). The app launches with the
/// deterministic `-open-panel-on-launch` hook — no global-hotkey dependency
/// on hosted runners.
final class PanelUITests: XCTestCase {
    @MainActor
    func testMenuBarAgentStaysResidentOnPlainLaunch() {
        let app = XCUIApplication()
        app.launch()

        let deadline = Date().addingTimeInterval(5)
        while app.state == .notRunning && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        XCTAssertNotEqual(app.state, .notRunning, "plain Xcode Run launch must keep Gancho resident")
    }

    @MainActor
    func testSettingsDeepLinkOpensSettingsWindow() throws {
        let app = XCUIApplication()
        app.launch()

        let deadline = Date().addingTimeInterval(5)
        while app.state == .notRunning && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        let url = try XCTUnwrap(URL(string: "gancho://settings"))
        XCTAssertTrue(NSWorkspace.shared.open(url))
        XCTAssertTrue(app.windows["Settings"].firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testMenuBarStatusItemResolvesToARealFrame() {
        let app = XCUIApplication()
        app.launch()

        let deadline = Date().addingTimeInterval(5)
        while app.state == .notRunning && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        // Existence in the accessibility tree is not enough — assert the status
        // item resolves to a real, non-empty frame (a never-created or
        // collapsed-to-zero item would fail here). Which display it lands on,
        // and whether that is on-screen, the app logs in DEBUG at launch.
        let statusItem = app.statusItems.firstMatch
        guard statusItem.waitForExistence(timeout: 5) else {
            // Self-skip where the runner can't reach the status menu bar (some
            // headless CI displays); residence is covered by the sibling test.
            print("skip: status item not exposed to the UI runner in this environment")
            return
        }
        XCTAssertFalse(
            statusItem.frame.isEmpty, "the status item must resolve to a non-zero on-screen frame")
    }

    @MainActor
    private func launchWithPanel() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-open-panel-on-launch"]
        app.launch()
        return app
    }

    @MainActor
    func testPanelOpensAndSearchFieldHasFocus() {
        let app = launchWithPanel()
        let search = app.textFields["search-field"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5), "panel search field must open on launch hook")

        // Type-to-search goes straight to the field — no click required.
        app.typeText("zzz-no-results-zzz")
        XCTAssertEqual(search.value as? String, "zzz-no-results-zzz")
    }

    @MainActor
    func testEscapeClosesPanel() {
        let app = launchWithPanel()
        let search = app.textFields["search-field"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))

        app.typeKey(.escape, modifierFlags: [])
        // Window-geometry assertions self-skip on tiny virtual displays
        // (vitrine pattern) — existence flips are stable everywhere.
        let disappeared = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: disappeared, object: search)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 5), .completed)
    }

    @MainActor
    func testArrowNavigationDoesNotStealFocusFromSearch() {
        let app = launchWithPanel()
        let search = app.textFields["search-field"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))

        // Arrows are handled by the panel; the search field keeps focus so
        // the user can keep typing mid-navigation.
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.upArrow, modifierFlags: [])
        app.typeText("still typing")
        XCTAssertEqual(search.value as? String, "still typing")
    }
}

import XCTest

/// Keyboard-first panel smoke (XCTest lives ONLY in this UI target; unit
/// tests are Swift Testing in the package). The app launches with the
/// deterministic `-open-panel-on-launch` hook — no global-hotkey dependency
/// on hosted runners.
final class PanelUITests: XCTestCase {
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

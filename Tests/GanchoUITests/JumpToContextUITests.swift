import XCTest

/// ⌘J on a result lists the clips copied within two minutes of it; esc goes
/// back to the results on the same row.
final class JumpToContextUITests: XCTestCase {
    @MainActor
    private func launch(appearance: String = "light") -> XCUIApplication {
        continueAfterFailure = false
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item", "-use-temp-durable-store",
            "-seed-context-session", "-force-free-tier", "-start-capture-paused",
            "-suppress-paused-notice-for-ui-test", "-suppress-storage-notice-for-ui-test",
            "-ui-test-paste-sink", "copy-only", "-place-panel-for-ui-test",
            "-opaque-panel-for-ui-test", "-AppleLanguages", "(en)", "-appearance", appearance,
            "-telemetry-consent", "disabled", "-ui-test-defaults-suite",
            "com.johnny4young.gancho.uitests.context.\(UUID().uuidString)"
        ]
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 5)
        return app
    }

    @MainActor
    private func rows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "clip-row")
    }

    @MainActor
    private func row(containing text: String, in app: XCUIApplication) -> XCUIElement {
        rows(app).matching(NSPredicate(format: "label CONTAINS %@", text)).firstMatch
    }

    @MainActor
    private func header(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["context-header"].firstMatch
    }

    @MainActor
    private func waitForCount(_ count: Int, in app: XCUIApplication) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count == %d", count), object: rows(app))
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }

    @MainActor
    func testCommandJShowsTheSessionAndEscReturns() throws {
        let app = launch()
        defer { app.terminate() }
        let anchor = row(containing: "becomesKeyOnlyIfNeeded", in: app)
        XCTAssertTrue(anchor.waitForExistence(timeout: 15))
        XCTAssertTrue(waitForCount(6, in: app))
        try SynthesizedInput.requireForeground(app)
        // Newest first: the link, the fix, then the code. The keys stay in the search field.
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.downArrow, modifierFlags: [])

        let peekAction = app.descendants(matching: .any)["preview-context"].firstMatch
        XCTAssertTrue(peekAction.waitForExistence(timeout: 5), "the peek offers Show context")
        try keepRender(of: "history-panel", in: app, named: "Show context in the peek")

        app.typeKey("j", modifierFlags: .command)
        XCTAssertTrue(header(app).waitForExistence(timeout: 5))
        XCTAssertFalse(peekAction.exists, "not offered again inside context mode")
        XCTAssertTrue(
            waitForCount(5, in: app),
            "the session, without the lunch order: \(rows(app).allElementsBoundByIndex.map(\.label))"
        )
        XCTAssertFalse(row(containing: "Lunch order", in: app).exists)
        XCTAssertTrue(app.descendants(matching: .any)["context-match"].firstMatch.exists)
        try keepRender(of: "history-panel", in: app, named: "Jump to context")

        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(header(app).waitForNonExistence(timeout: 5))
        XCTAssertTrue(waitForCount(6, in: app))
        XCTAssertTrue(
            app.descendants(matching: .any)["history-panel"].firstMatch.exists,
            "esc leaves context mode before it hides the panel")
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isSelected == true OR value == %@", "Selected"),
            object: anchor)
        XCTAssertEqual(
            XCTWaiter.wait(for: [selected], timeout: 5), .completed,
            "back on the row ⌘J was pressed on")
    }

    @MainActor
    func testShowContextFromTheRowMenu() throws {
        let app = launch()
        defer { app.terminate() }
        let link = row(containing: "gancho.app/docs/panel", in: app)
        XCTAssertTrue(link.waitForExistence(timeout: 15))
        try SynthesizedInput.requireForeground(app)
        link.rightClick()
        let item = app.menuItems["row-show-context"].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 3))
        item.click()
        XCTAssertTrue(header(app).waitForExistence(timeout: 5))
        // 2 min before the last clip: the code, the fix and the link itself.
        XCTAssertTrue(waitForCount(3, in: app))
    }
}

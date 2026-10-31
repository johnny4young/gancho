import XCTest

/// A paste-stack run: the queue keeps what went in, marks what comes next,
/// and Skip / Back / Reset move the cursor without pasting.
final class PasteStackRunUITests: XCTestCase {
    @MainActor
    func testRunKeepsPastedRowsAndMovesTheCursor() throws {
        let nonce = UUID().uuidString
        let app = launchPanel(nonce: nonce)
        defer { app.terminate() }
        let strip = app.buttons["paste-stack-strip"].firstMatch
        XCTAssertTrue(strip.waitForExistence(timeout: 15))
        strip.click()

        let rows = app.descendants(matching: .any).matching(identifier: "paste-stack-row")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows.element(boundBy: 0).value as? String, "Next")

        app.buttons["paste-stack-skip"].firstMatch.click()
        XCTAssertTrue(waitForValue("Next", of: rows.element(boundBy: 1)))
        app.buttons["paste-stack-back"].firstMatch.click()
        XCTAssertTrue(waitForValue("Next", of: rows.element(boundBy: 0)))

        // Pasting hides the panel, as it does for a real paste; reopen it.
        app.buttons["paste-stack-next"].firstMatch.click()
        GanchoUITestCommands.post("openPanel", token: nonce)
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
        XCTAssertTrue(strip.label.contains("2 of 2"), strip.label)
        strip.click()
        XCTAssertTrue(waitForValue("Pasted", of: rows.element(boundBy: 0)))
        XCTAssertEqual(rows.element(boundBy: 1).value as? String, "Next")
        XCTAssertEqual(rows.count, 2, "a pasted row stays in the run")

        app.buttons["paste-stack-reset"].firstMatch.click()
        XCTAssertTrue(waitForValue("Next", of: rows.element(boundBy: 0)))
    }

    @MainActor
    private func waitForValue(_ value: String, of element: XCUIElement) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", value), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 5) == .completed
    }

    @MainActor
    private func launchPanel(nonce: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item", "-use-temp-durable-store",
            "-seed-visual-library", "-seed-paste-stack", "-force-free-tier",
            "-start-capture-paused", "-opaque-panel-for-ui-test", "-place-panel-for-ui-test",
            "-ui-test-paste-sink", "pasted", "-command-nonce", nonce,
            "-suppress-storage-notice-for-ui-test", "-AppleLanguages", "(en)",
            "-panel-content-width", "720", "-panel-content-height", "460",
            "-ui-test-defaults-suite",
            "com.johnny4young.gancho.uitests.stack.\(UUID().uuidString)"
        ]
        app.launch()
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        return app
    }
}

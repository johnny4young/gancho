import XCTest

/// The panel's header contract (one toolbar: boards, type filters, Save filter)
/// plus kept visual evidence of the redesigned rows and peek over synthetic
/// clips. The opaque panel keeps the desktop out of the capture.
final class PanelAppearanceUITests: XCTestCase {
    @MainActor
    func testToolbarAndRowsRenderOverSeededHistory() throws {
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item", "-use-temp-durable-store",
            "-seed-visual-library", "-seed-source-apps", "-force-free-tier",
            "-opaque-panel-for-ui-test", "-place-panel-for-ui-test",
            "-suppress-storage-notice-for-ui-test", "-AppleLanguages", "(en)",
            "-ui-test-defaults-suite",
            "com.johnny4young.gancho.uitests.appearance.\(UUID().uuidString)"
        ]
        app.launch()
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        defer { app.terminate() }

        let search = app.textFields["search-field"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        XCTAssertTrue(app.descendants(matching: .any)["board-rail"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["filter-rail"].firstMatch.exists)
        XCTAssertTrue(app.buttons["filter-save"].firstMatch.exists)
        XCTAssertTrue(app.buttons["board-new"].firstMatch.exists)

        let rows = app.descendants(matching: .any).matching(identifier: "clip-row")
        XCTAssertTrue(
            rows.element(boundBy: 2).waitForExistence(timeout: 10),
            "the seeded history must show at least three rows")
        XCTAssertEqual(rows.allElementsBoundByIndex.filter(\.isSelected).count, 1)

        let secondRow = rows.element(boundBy: 1)
        secondRow.click()
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isSelected == true"), object: secondRow)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 3), .completed)
        XCTAssertTrue(
            app.descendants(matching: .any)["preview-title"].firstMatch.waitForExistence(
                timeout: 5),
            "selecting a row must open the peek beside the list")

        let panel = app.dialogs["history-panel"].firstMatch
        XCTAssertTrue(panel.exists)
        let screenshot = XCTAttachment(screenshot: panel.screenshot())
        screenshot.name = "History panel — toolbar, rows and peek"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}

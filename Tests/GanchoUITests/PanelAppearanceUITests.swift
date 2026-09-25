import XCTest

/// The panel's header contract (one toolbar: boards, type filters, Save filter)
/// plus kept visual evidence of the redesigned rows and peek over synthetic
/// clips. The opaque panel keeps the desktop out of the capture.
final class PanelAppearanceUITests: XCTestCase {
    @MainActor
    func testToolbarAndRowsRenderOverSeededHistory() throws {
        try verifyToolbar(language: "en", extraArguments: [])
    }

    @MainActor
    func testCompactSpanishToolbarWithLargeTextAndSourceFilter() throws {
        try verifyToolbar(
            language: "es",
            extraArguments: [
                "-panel-content-width", "720", "-panel-content-height", "460",
                "-panel-text-size", "large"
            ])
    }

    @MainActor
    private func verifyToolbar(language: String, extraArguments: [String]) throws {
        continueAfterFailure = false
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item", "-use-temp-durable-store",
            "-seed-visual-library", "-seed-source-apps", "-seed-sample-boards", "-force-free-tier",
            "-start-capture-paused",
            "-opaque-panel-for-ui-test", "-place-panel-for-ui-test",
            "-suppress-storage-notice-for-ui-test", "-AppleLanguages", "(\(language))",
            "-ui-test-defaults-suite",
            "com.johnny4young.gancho.uitests.appearance.\(UUID().uuidString)"
        ]
        app.launchArguments += extraArguments
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

        let panel = app.dialogs["history-panel"].firstMatch
        let source = app.descendants(matching: .any)["source-app-filter"].firstMatch
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.click()
        let safari = app.menuItems["source-app-com.apple.Safari"].firstMatch
        XCTAssertTrue(safari.waitForExistence(timeout: 5))
        safari.click()
        let rail = app.descendants(matching: .any)["filter-rail"].firstMatch
        let boardRail = app.descendants(matching: .any)["board-rail"].firstMatch
        let save = app.buttons["filter-save"].firstMatch
        for control in [rail, source, save, boardRail] {
            XCTAssertTrue(
                panel.frame.insetBy(dx: -1, dy: -1).contains(control.frame),
                "\(control.identifier): \(control.frame) must fit in \(panel.frame)")
        }
        XCTAssertLessThanOrEqual(rail.frame.maxX, source.frame.minX + 1)
        XCTAssertLessThanOrEqual(source.frame.maxX, save.frame.minX + 1)
        source.click()
        let allApps = app.menuItems["source-app-all"].firstMatch
        XCTAssertTrue(allApps.waitForExistence(timeout: 5))
        allApps.click()

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

        XCTAssertTrue(panel.exists)
        attachPanel(panel)
        try verifyBoardKeyboardScroll(in: app)
    }

    @MainActor
    private func attachPanel(_ panel: XCUIElement) {
        let screenshot = XCTAttachment(screenshot: panel.screenshot())
        screenshot.name = "History panel — toolbar, rows and peek"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    private func verifyBoardKeyboardScroll(in app: XCUIApplication) throws {
        let search = app.textFields["search-field"].firstMatch
        search.click()
        try SynthesizedInput.requireForeground(app)
        // The preceding assertion selected row 1; return to row 0, then enter both rails.
        for _ in 0..<3 { app.typeKey(.upArrow, modifierFlags: []) }
        for _ in 0..<4 { app.typeKey(.rightArrow, modifierFlags: []) }
        let rail = app.descendants(matching: .any)["board-rail"].firstMatch
        let boards = rail.buttons.matching(NSPredicate(format: "label BEGINSWITH 'Seed board'"))
            .allElementsBoundByIndex
        XCTAssertEqual(boards.count, 3)
        XCTAssertTrue(
            try XCTUnwrap(boards.last).isHittable,
            "Keyboard focus must reveal a board outside the rail's viewport")
    }
}

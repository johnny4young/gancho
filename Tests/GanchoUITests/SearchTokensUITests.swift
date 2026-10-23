import XCTest

/// Filter tokens and the four search modes inside the panel's field.
final class SearchTokensUITests: XCTestCase {
    @MainActor
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item", "-use-temp-durable-store",
            "-seed-source-apps", "-force-free-tier", "-start-capture-paused",
            "-opaque-panel-for-ui-test", "-place-panel-for-ui-test",
            "-suppress-storage-notice-for-ui-test", "-suppress-paused-notice-for-ui-test",
            "-AppleLanguages", "(en)",
            "-ui-test-defaults-suite", "com.johnny4young.gancho.uitests.tokens.\(UUID().uuidString)"
        ]
        app.launch()
        app.activate()
        return app
    }

    @MainActor
    private func waitForRows(_ count: Int, in app: XCUIApplication) -> Bool {
        let rows = app.descendants(matching: .any).matching(identifier: "clip-row")
        let deadline = Date().addingTimeInterval(10)
        while rows.count != count, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return rows.count == count
    }

    @MainActor
    func testTabTurnsATokenIntoAChipAndItsCrossRemovesIt() throws {
        let app = launch()
        defer { app.terminate() }
        let field = app.textFields["search-field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        XCTAssertTrue(waitForRows(3, in: app))

        try typeTextReliably("app:xc", into: field, in: app)
        let popover = app.descendants(matching: .any)["search-token-popover"].firstMatch
        XCTAssertTrue(popover.waitForExistence(timeout: 5))
        field.typeKey(.tab, modifierFlags: [])
        let appChip = app.descendants(matching: .any)["search-token-chip-app"].firstMatch
        XCTAssertTrue(appChip.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String ?? "", "")
        XCTAssertTrue(waitForRows(1, in: app), "app: keeps only that app's clips")

        field.typeText("type:links ")
        XCTAssertTrue(
            app.descendants(matching: .any)["search-token-chip-type"].firstMatch.waitForExistence(
                timeout: 5))
        XCTAssertTrue(waitForRows(0, in: app), "no Xcode clip is a link")

        app.buttons["search-token-remove-type"].firstMatch.click()
        XCTAssertTrue(waitForRows(1, in: app), "× removes its filter")
        app.buttons["search-token-remove-app"].firstMatch.click()
        XCTAssertTrue(appChip.waitForNonExistence(timeout: 5))
        XCTAssertTrue(waitForRows(3, in: app))
    }

    @MainActor
    func testModeControlSetsTheModeAndShiftCommandSSavesTheFilter() throws {
        let app = launch()
        defer { app.terminate() }
        let field = app.textFields["search-field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        let exact = app.buttons["search-mode-exact"].firstMatch
        XCTAssertTrue(exact.waitForExistence(timeout: 5))
        exact.click()
        XCTAssertTrue(exact.isSelected)

        try typeTextReliably("source sample", into: field, in: app)
        XCTAssertTrue(waitForRows(1, in: app))
        let header = app.staticTexts.matching(
            NSPredicate(format: "label ==[c] %@ OR value ==[c] %@", "Exact", "Exact")
        ).firstMatch
        XCTAssertTrue(header.exists, "the results header names the mode")

        field.typeKey("s", modifierFlags: [.command, .shift])
        XCTAssertTrue(
            app.textFields["filter-name-field"].firstMatch.waitForExistence(timeout: 5),
            "⇧⌘S opens the saved-filter sheet")
    }

    @MainActor
    func testNoResultsOffersTheOtherModesAndDownArrowTakesTheBest() throws {
        let app = launch()
        defer { app.terminate() }
        let field = app.textFields["search-field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        app.buttons["search-mode-exact"].firstMatch.click()
        try typeTextReliably("source alp", into: field, in: app)
        XCTAssertTrue(waitForRows(0, in: app), "an exact phrase needs whole words")

        let fuzzy = app.buttons["no-results-alt-fuzzy"].firstMatch
        XCTAssertTrue(fuzzy.waitForExistence(timeout: 5))
        XCTAssertTrue(fuzzy.isSelected, "the most results is highlighted")
        XCTAssertTrue(app.buttons["no-results-alt-regex"].firstMatch.exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["no-results-stage"].firstMatch.exists,
            "the peek previews the best alternative")

        field.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(waitForRows(1, in: app), "↓ applies the best alternative")
        let selected = ["exact", "fuzzy", "regex", "meaning"].filter {
            app.buttons["search-mode-\($0)"].firstMatch.isSelected
        }
        XCTAssertEqual(selected, ["fuzzy"])
    }
}

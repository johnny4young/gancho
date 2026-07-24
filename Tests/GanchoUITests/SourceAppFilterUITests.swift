import XCTest

final class SourceAppFilterUITests: XCTestCase {
    @MainActor
    func testSourceAppFilterNarrowsThePanelAndCapturesEvidence() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item",
            "-use-temp-durable-store", "-seed-source-apps",
            "-place-panel-for-ui-test",
            "-AppleLanguages", "(en)"
        ]
        app.launch()
        defer { app.terminate() }

        let filter = app.descendants(matching: .any)["source-app-filter"].firstMatch
        guard filter.waitForExistence(timeout: 10), filter.isHittable else {
            throw XCTSkip("source-app filter is not reachable on this runner")
        }
        filter.click()

        let safari = app.descendants(matching: .any)["Safari"].firstMatch
        XCTAssertTrue(safari.waitForExistence(timeout: 4), "Safari source filter is missing")
        XCTAssertTrue(safari.isHittable, "Safari source filter is not hittable")
        safari.click()

        // ClipCard intentionally combines kind + preview into one accessible
        // row (for example, "text, Safari source alpha"). Query that public
        // row contract instead of assuming the preview is a standalone text.
        let safariAlpha = clipRow(containing: "Safari source alpha", in: app)
        let safariLink = clipRow(containing: "Safari source link", in: app)
        let xcodeSample = clipRow(containing: "Xcode source sample", in: app)
        XCTAssertTrue(safariAlpha.waitForExistence(timeout: 5))
        XCTAssertTrue(safariLink.waitForExistence(timeout: 5))
        let xcodeDisappeared = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: xcodeSample)
        XCTAssertEqual(
            XCTWaiter.wait(for: [xcodeDisappeared], timeout: 5), .completed,
            "the Safari filter must remove Xcode rows after the async search refresh")

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "macOS source-app filter — Safari"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testNoResultsKeepsClearFiltersActionAccessible() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item",
            "-use-temp-durable-store", "-seed-source-apps",
            "-place-panel-for-ui-test",
            "-AppleLanguages", "(en)"
        ]
        app.launch()
        defer { app.terminate() }

        let filter = app.descendants(matching: .any)["source-app-filter"].firstMatch
        XCTAssertTrue(filter.waitForExistence(timeout: 10))
        XCTAssertTrue(filter.isHittable)
        filter.click()

        let safari = app.descendants(matching: .any)["Safari"].firstMatch
        XCTAssertTrue(safari.waitForExistence(timeout: 4))
        XCTAssertTrue(safari.isHittable)
        safari.click()

        let field = app.textFields["search-field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        try typeTextReliably("Xcode source sample", into: field, in: app)

        let emptyState = app.descendants(matching: .any)["panel-empty-noresults"].firstMatch
        XCTAssertTrue(
            emptyState.waitForExistence(timeout: 5),
            "the mismatched query and source filter must expose the no-results state")

        let clearFilters = app.buttons["clear-filters"].firstMatch
        XCTAssertTrue(
            clearFilters.waitForExistence(timeout: 3),
            "the actionable child must remain exposed to accessibility")
        XCTAssertTrue(clearFilters.isHittable)
        clearFilters.click()

        XCTAssertTrue(
            clipRow(containing: "Xcode source sample", in: app).waitForExistence(timeout: 5),
            "clearing the source filter must preserve the query and reveal its matching row")
    }

    @MainActor
    private func clipRow(containing preview: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(
            NSPredicate(format: "identifier == 'clip-row' AND label CONTAINS %@", preview)
        ).firstMatch
    }
}

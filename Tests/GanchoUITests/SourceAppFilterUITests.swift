import XCTest

final class SourceAppFilterUITests: XCTestCase {
    /// Shared launch arguments: an open panel, an in-process status item, a
    /// throwaway store seeded with source-app fixtures, and a deterministic
    /// panel placement so the runner can reach the controls.
    private static let launchArguments = [
        "-open-panel-on-launch", "-use-in-process-status-item",
        "-use-temp-durable-store", "-seed-source-apps",
        "-place-panel-for-ui-test",
        "-AppleLanguages", "(en)"
    ]

    @MainActor
    private func launchSeededPanel() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = Self.launchArguments
        app.launch()
        return app
    }

    /// Opens the source-app filter and narrows the panel to Safari.
    ///
    /// Reaching the filter is an ENVIRONMENT condition — a headless or
    /// mispositioned runner cannot hit it — so it skips instead of failing,
    /// the same contract the rest of this target uses for synthesized input.
    /// Safari's presence is a seeded-content contract, so it stays a hard
    /// assertion. Both tests enter through here so neither can drift into
    /// failing where the other skips.
    @MainActor
    private func selectSafariSourceFilter(in app: XCUIApplication) throws {
        let filter = app.descendants(matching: .any)["source-app-filter"].firstMatch
        guard filter.waitForExistence(timeout: 10), filter.isHittable else {
            throw XCTSkip("source-app filter is not reachable on this runner")
        }
        filter.click()

        let safari = app.descendants(matching: .any)["Safari"].firstMatch
        XCTAssertTrue(safari.waitForExistence(timeout: 4), "Safari source filter is missing")
        XCTAssertTrue(safari.isHittable, "Safari source filter is not hittable")
        safari.click()
    }

    @MainActor
    func testSourceAppFilterNarrowsThePanelAndCapturesEvidence() throws {
        let app = launchSeededPanel()
        defer { app.terminate() }

        try selectSafariSourceFilter(in: app)

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
        let app = launchSeededPanel()
        defer { app.terminate() }

        try selectSafariSourceFilter(in: app)

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

    /// A filter alone can empty the list, with no query typed at all. That
    /// state must read as "no matches" and keep a way back — never as first
    /// run, which would claim the history is empty and offer no way to undo
    /// the narrowing.
    @MainActor
    func testFilterOnlyEmptyStateIsNotADeadEnd() throws {
        let app = launchSeededPanel()
        defer { app.terminate() }

        let images = app.buttons["Images"].firstMatch
        guard images.waitForExistence(timeout: 10), images.isHittable else {
            throw XCTSkip("kind filter pills are not reachable on this runner")
        }
        images.click()

        // The seed carries text, link, and code clips only, so Images empties
        // the list while the search field stays empty.
        let noResults = app.descendants(matching: .any)["panel-empty-noresults"].firstMatch
        XCTAssertTrue(
            noResults.waitForExistence(timeout: 5),
            "a filter-only empty list must not present the first-run state")
        XCTAssertFalse(
            app.descendants(matching: .any)["panel-empty-firstrun"].exists,
            "history is not empty here — only the filter is narrowing it")

        let clearFilters = app.buttons["clear-filters"].firstMatch
        XCTAssertTrue(
            clearFilters.waitForExistence(timeout: 3),
            "the filter-only empty state must offer a way back")
        XCTAssertTrue(clearFilters.isHittable)
        clearFilters.click()

        XCTAssertTrue(
            clipRow(containing: "Safari source alpha", in: app).waitForExistence(timeout: 5),
            "clearing the filter must restore the seeded rows")
    }

    @MainActor
    private func clipRow(containing preview: String, in app: XCUIApplication) -> XCUIElement {
        app.staticTexts.matching(
            NSPredicate(format: "identifier == 'clip-row' AND label CONTAINS %@", preview)
        ).firstMatch
    }
}

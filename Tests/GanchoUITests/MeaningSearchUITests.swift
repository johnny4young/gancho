import XCTest

final class MeaningSearchUITests: XCTestCase {
    @MainActor func testEnglishLight() throws { try verify("en", "light") }
    @MainActor func testEnglishDark() throws { try verify("en", "dark") }
    @MainActor func testSpanishLight() throws { try verify("es", "light") }
    @MainActor func testSpanishDark() throws { try verify("es", "dark") }
    @MainActor private func verify(_ language: String, _ appearance: String) throws {
        continueAfterFailure = false
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item", "-use-temp-durable-store",
            "-seed-source-apps", "-force-free-tier", "-start-capture-paused",
            "-ui-test-related-results",
            "-ui-test-defaults-suite", "com.johnny4young.gancho.uitests.meaning.\(UUID())",
            "-opaque-panel-for-ui-test", "-place-panel-for-ui-test", "-AppleLanguages",
            "(\(language))",
            "-appearance", appearance, "-panel-content-width", "720", "-panel-content-height",
            "460",
            "-panel-text-size", "large"
        ]
        app.launch()
        defer { app.terminate() }
        app.activate()
        let rows = app.descendants(matching: .any).matching(identifier: "clip-row")
        XCTAssertTrue(rows.firstMatch.appears(within: 10))
        let meaning = app.buttons["search-mode-meaning"].firstMatch
        XCTAssertTrue(meaning.appears(within: 5))
        let query = app.textFields["search-field"].firstMatch
        XCTAssertTrue(query.exists)
        try typeTextReliably("syntheticnomatch", into: query, in: app)
        let noResults = app.descendants(matching: .any)["panel-empty-noresults"].firstMatch
        XCTAssertTrue(noResults.appears(within: 5))
        meaning.click()
        XCTAssertTrue(
            rows.firstMatch.appears(within: 5),
            "Meaning lists the related clips; query \(query.value ?? "nil"), selected "
                + "\(meaning.isSelected), status "
                + "\(app.descendants(matching: .any)["meaning-search-status"].firstMatch.label)")
        XCTAssertTrue(
            app.descendants(matching: .any)["meaning-search-status"].firstMatch.exists)
        try keepRender(
            of: "history-panel", in: app,
            named: "Meaning search synthetic routing — \(language) — \(appearance)")
        app.buttons["search-mode-fuzzy"].firstMatch.click()
        XCTAssertTrue(noResults.appears(within: 5), "Fuzzy has no related rows")
    }
}

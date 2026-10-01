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
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
        let toggle = app.descendants(matching: .any)["meaning-search-toggle"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        let query = app.textFields["search-field"].firstMatch
        XCTAssertTrue(query.exists)
        query.click()
        query.typeText("syntheticnomatch")
        XCTAssertTrue(
            app.descendants(matching: .any)["panel-empty-noresults"].firstMatch.waitForExistence(
                timeout: 5))
        toggle.click()
        let heading = app.descendants(matching: .any)["meaning-related-heading"].firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: 5))
        XCTAssertTrue(rows.firstMatch.exists)
        let attachment = XCTAttachment(
            screenshot: app.dialogs["history-panel"].firstMatch.screenshot())
        attachment.name = "Meaning search synthetic routing — \(language) — \(appearance)"
        attachment.lifetime = .keepAlways
        add(attachment)
        toggle.click()
        XCTAssertTrue(heading.waitForNonExistence(timeout: 5))
    }
}

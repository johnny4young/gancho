import XCTest

/// Launches without `-open-panel-on-launch`, so the panel is prewarmed the way
/// it is in production and every open arrives through the show notification.
final class PanelPrewarmedOpenUITests: XCTestCase {
    @MainActor
    func testEveryOpenStartsOnTheNewestClipWithSearchFocused() throws {
        let settingsURL = try XCTUnwrap(URL(string: "gancho://settings"))
        let token = UUID().uuidString
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-regular-activation-for-ui-tests", "-use-in-process-status-item",
            "-command-nonce", token, "-open-deep-link-on-launch", settingsURL.absoluteString,
            "-use-temp-durable-store", "-seed-source-apps", "-start-capture-paused",
            "-opaque-panel-for-ui-test", "-suppress-storage-notice-for-ui-test",
            "-AppleLanguages", "(en)",
            "-ui-test-defaults-suite", "com.johnny4young.gancho.uitests.prewarm.\(token)"
        ]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.windows["Settings"].firstMatch.waitForExistence(timeout: 10))

        GanchoUITestCommands.post("openPanel", token: token)
        let panel = app.descendants(matching: .any)["history-panel"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        let rows = app.descendants(matching: .any).matching(identifier: "clip-row")
        XCTAssertTrue(rows.element(boundBy: 2).waitForExistence(timeout: 10))
        let newest = rows.element(boundBy: 0)
        XCTAssertTrue(newest.isSelected, "the first open selects the newest clip")
        let newestLabel = newest.label

        let search = app.textFields["search-field"].firstMatch
        try SynthesizedInput.requireForeground(app)
        XCTAssertTrue(SynthesizedInput.waitForKeyboardFocus(search, timeout: 5))
        search.typeKey(.downArrow, modifierFlags: [])
        XCTAssertTrue(rows.element(boundBy: 1).isSelected, "arrows move from the newest clip")

        search.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
        GanchoUITestCommands.post("openPanel", token: token)
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        let reopened = rows.element(boundBy: 0)
        XCTAssertTrue(reopened.waitForExistence(timeout: 5))
        XCTAssertEqual(reopened.label, newestLabel)
        XCTAssertTrue(reopened.isSelected, "a reopen starts from the newest clip again")
        XCTAssertTrue(
            SynthesizedInput.waitForKeyboardFocus(search, timeout: 5),
            "a reopen focuses the search field")
    }
}

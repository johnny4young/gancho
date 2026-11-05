import XCTest

final class TelemetryConsentUITests: XCTestCase {
    @MainActor
    func testTelemetryConsentStartsDisabledAndCanBeDeclined() throws {
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item",
            "-force-capture-active", "-force-pasteboard-access-allowed",
            "-disable-screen-share-auto-pause", "-show-telemetry-consent",
            "-telemetry-consent", "notAsked", "-AppleLanguages", "(en)"
        ]
        app.launch()
        defer { app.terminate() }

        let prompt = app.descendants(matching: .any)["telemetry-consent-prompt"].firstMatch
        XCTAssertTrue(prompt.waitForExistence(timeout: 5))
        let keepDisabled = app.buttons["Keep disabled"].firstMatch
        XCTAssertTrue(keepDisabled.waitForExistence(timeout: 2))

        app.activate()
        try SynthesizedInput.requireForeground(app)
        // The prompt is modal, so Accessibility reaches nothing behind it until it closes.
        let search = app.textFields["search-field"].firstMatch
        XCTAssertFalse(search.exists)
        guard keepDisabled.isCenterOnDisplay else {
            throw XCTSkip("telemetry consent prompt is off screen on this runner")
        }
        XCTAssertTrue(keepDisabled.waitForHittable(timeout: 5))
        keepDisabled.click()
        XCTAssertTrue(prompt.waitForNonExistence(timeout: 5))
        XCTAssertTrue(search.waitForExistence(timeout: 5))
    }
}

import XCTest

final class TelemetryConsentUITests: XCTestCase {
    @MainActor
    func testTelemetryConsentStartsDisabledAndCanBeDeclined() throws {
        let app = XCUIApplication()
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
        guard keepDisabled.isHittable else {
            throw XCTSkip("telemetry consent prompt is obscured on this runner")
        }
        keepDisabled.click()
        XCTAssertFalse(prompt.waitForExistence(timeout: 1))
    }
}

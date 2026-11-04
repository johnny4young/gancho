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
        // Accessibility's hit test misses this button, yet a click at its center lands.
        guard keepDisabled.isCenterOnDisplay else {
            throw XCTSkip("telemetry consent prompt is off screen on this runner")
        }
        keepDisabled.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCTAssertTrue(prompt.waitForNonExistence(timeout: 5))
    }
}

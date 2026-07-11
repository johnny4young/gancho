import XCTest

final class TelemetryConsentUITests: XCTestCase {
    @MainActor
    func testTelemetryConsentStartsDisabledAndCanBeDeclined() {
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
        app.buttons["Keep disabled"].firstMatch.click()
        XCTAssertFalse(prompt.waitForExistence(timeout: 1))
    }
}

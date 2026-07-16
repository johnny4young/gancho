import XCTest

/// iOS UI smoke for the Privacy Center error log — the iOS sibling of the macOS
/// `PanelUITests` coverage. XCTest lives ONLY in UI-test targets; package unit
/// tests use Swift Testing.
final class PrivacyCenterUITests: XCTestCase {
    @MainActor
    func testPrivacyCenterRecentIssuesLogsEphemeralStorage() {
        // Force the in-memory fallback so the model logs a content-free
        // "Storage" issue at construction, and route straight to the Privacy
        // Center (no welcome, no navigation).
        let app = XCUIApplication()
        app.launchArguments = ["-force-ephemeral-store", "-open-privacy-center-on-launch"]
        app.launch()
        defer { app.terminate() }

        let privacyCenter = app.descendants(matching: .any)["ios-privacy-center"].firstMatch
        XCTAssertTrue(
            privacyCenter.waitForExistence(timeout: 10),
            "the -open-privacy-center-on-launch hook must show the Privacy Center")
        XCTAssertTrue(
            app.descendants(matching: .any)["ios-successful-reuse-count"].firstMatch
                .waitForExistence(timeout: 5),
            "the Privacy Center must expose the in-memory successful-reuse count")

        // The ephemeral-store launch logged an issue, so the "Recent issues"
        // section must surface it with the Copy-for-support button — the
        // end-to-end proof that the error log records and renders on iOS.
        let copyButton = app.buttons["copy-diagnostics"].firstMatch
        for _ in 0..<3 {
            if copyButton.waitForExistence(timeout: 1) { break }
            privacyCenter.swipeUp()
        }
        XCTAssertTrue(
            copyButton.waitForExistence(timeout: 5),
            "an ephemeral-store launch must log a content-free issue shown in Recent issues")
    }

    @MainActor
    func testTelemetryConsentStartsDisabledAndCanBeDeclined() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-skip-welcome-on-launch", "-force-ephemeral-store",
            "-show-telemetry-consent", "-telemetry-consent", "notAsked",
            "-AppleLanguages", "(en)"
        ]
        app.launch()
        defer { app.terminate() }

        let alert = app.alerts["Help improve Gancho?"].firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        alert.buttons["Keep disabled"].tap()
        XCTAssertFalse(alert.waitForExistence(timeout: 1))
    }
}

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

        let privacyCenter = app.descendants(matching: .any)["ios-privacy-center"].firstMatch
        XCTAssertTrue(
            privacyCenter.waitForExistence(timeout: 10),
            "the -open-privacy-center-on-launch hook must show the Privacy Center")

        // The ephemeral-store launch logged an issue, so the "Recent issues"
        // section must surface it with the Copy-for-support button — the
        // end-to-end proof that the error log records and renders on iOS.
        let copyButton = app.buttons["copy-diagnostics"].firstMatch
        XCTAssertTrue(
            copyButton.waitForExistence(timeout: 5),
            "an ephemeral-store launch must log a content-free issue shown in Recent issues")
    }
}

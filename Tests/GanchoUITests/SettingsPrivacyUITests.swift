import XCTest

/// Privacy-facing Settings coverage and release-safe visual evidence. Screenshots
/// stay scoped to Gancho's opaque Settings window so unrelated desktop content
/// never enters a kept test attachment.
final class SettingsPrivacyUITests: XCTestCase {
    @MainActor
    func testSpotlightIndexingExplainsThePrivacyBoundaryAndCapturesEvidence() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-regular-activation-for-ui-tests", "-use-in-process-status-item",
            "-use-temp-durable-store", "-start-capture-paused",
            "-ui-test-defaults-suite", "com.johnny4young.gancho.uitests.settings-privacy",
            "-open-deep-link-on-launch", "gancho://settings",
            "-AppleLanguages", "(en)"
        ]
        app.launch()
        defer { app.terminate() }

        let settings = app.windows["Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 8))

        let privacyTab = app.buttons["settings-tab-privacy"].firstMatch
        XCTAssertTrue(privacyTab.waitForExistence(timeout: 3))
        privacyTab.click()

        let spotlightToggle = app.switches["spotlight-indexing-toggle"].firstMatch
        XCTAssertTrue(spotlightToggle.waitForExistence(timeout: 3))
        let privacyNote = app.staticTexts["spotlight-indexing-privacy-note"].firstMatch
        XCTAssertTrue(privacyNote.waitForExistence(timeout: 3))

        let privacySettings = try XCTUnwrap(
            settings.scrollViews.allElementsBoundByIndex.first {
                $0.frame.height > 200 && $0.frame.contains(spotlightToggle.frame)
            },
            "the vertical Privacy form must be exposed as a scroll view")
        privacySettings.scroll(byDeltaX: 0, deltaY: -140)

        let attachment = XCTAttachment(screenshot: privacySettings.screenshot())
        attachment.name = "settings-spotlight-indexing"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

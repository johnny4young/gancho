import XCTest

/// Privacy-facing Settings coverage and release-safe visual evidence. The app
/// renders its own Settings window, so unrelated desktop content never enters
/// a kept test attachment.
final class SettingsPrivacyUITests: XCTestCase {
    @MainActor
    func testSpotlightIndexingExplainsThePrivacyBoundaryAndCapturesEvidence() throws {
        let app = try launchSettingsWindow(extraArguments: [
            "-use-temp-durable-store", "-start-capture-paused",
            "-ui-test-defaults-suite", "com.johnny4young.gancho.uitests.settings-privacy"
        ])
        defer { app.terminate() }
        let settings = app.windows["Settings"].firstMatch

        let privacyTab = app.buttons["settings-tab-privacy"].firstMatch
        XCTAssertTrue(privacyTab.waitForExistence(timeout: 3))
        privacyTab.click()

        let spotlightToggle = app.switches["spotlight-indexing-toggle"].firstMatch
        XCTAssertTrue(spotlightToggle.waitForExistence(timeout: 3))
        let privacyNote = app.staticTexts["spotlight-indexing-privacy-note"].firstMatch
        XCTAssertTrue(privacyNote.waitForExistence(timeout: 3))

        let privacySettings = settings.scrollViews
            .containing(.any, identifier: "spotlight-indexing-toggle").firstMatch
        XCTAssertTrue(
            privacySettings.exists, "the vertical Privacy form must be exposed as a scroll view")
        privacySettings.scroll(byDeltaX: 0, deltaY: -140)

        try keepRender(of: "Settings", in: app, named: "settings-spotlight-indexing")
    }

    @MainActor
    func testPrivateModeAutoOffDefaultsToOneHour() throws {
        let app = try launchSettingsWindow(extraArguments: [
            "-use-temp-durable-store", "-start-capture-paused",
            "-ui-test-defaults-suite",
            "com.johnny4young.gancho.uitests.settings-auto-off.\(UUID().uuidString)"
        ])
        defer { app.terminate() }
        let privacyTab = app.buttons["settings-tab-privacy"].firstMatch
        XCTAssertTrue(privacyTab.waitForExistence(timeout: 3))
        privacyTab.click()

        let picker = app.popUpButtons["private-mode-auto-off-picker"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 3))
        XCTAssertEqual(picker.value as? String, "1 hour")
        picker.click()
        let never = app.menuItems["Until I turn it off"].firstMatch
        XCTAssertTrue(never.waitForExistence(timeout: 3))
        never.click()
        XCTAssertEqual(picker.value as? String, "Until I turn it off")
    }

    /// Four answers before any toggle, and the Privacy Center one click away on every pane.
    @MainActor
    func testStatusTilesAndThePrivacyCenterCard() throws {
        let app = try launchSettingsWindow(extraArguments: [
            "-use-temp-durable-store", "-start-capture-paused",
            "-ui-test-defaults-suite",
            "com.johnny4young.gancho.uitests.settings-tiles.\(UUID().uuidString)"
        ])
        defer { app.terminate() }
        let settings = app.windows["Settings"].firstMatch
        let privacyTab = settings.buttons["settings-tab-privacy"].firstMatch
        XCTAssertTrue(privacyTab.waitForExistence(timeout: 3))
        privacyTab.click()
        for id in [
            "privacy-status-capturing", "privacy-status-encrypted", "privacy-status-skipped",
            "privacy-status-sync"
        ] {
            XCTAssertTrue(
                settings.descendants(matching: .any)[id].firstMatch.waitForExistence(timeout: 5), id
            )
        }
        let encrypted = settings.descendants(matching: .any)["privacy-status-encrypted"].firstMatch
        let verified = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "label CONTAINS %@ OR value CONTAINS %@", "Encrypted at rest",
                "Encrypted at rest"),
            object: encrypted)
        XCTAssertEqual(XCTWaiter.wait(for: [verified], timeout: 5), .completed)

        settings.buttons["settings-tab-retention"].firstMatch.click()
        let card = settings.buttons["settings-privacy-center-card"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        card.click()
        XCTAssertTrue(
            app.descendants(matching: .any)["privacy-center"].firstMatch
                .waitForExistence(timeout: 5))
    }
}

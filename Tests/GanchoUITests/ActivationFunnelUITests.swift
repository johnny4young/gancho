import Foundation
import XCTest

/// First-value smoke over the real macOS shell: onboarding walks its four
/// steps, offers the no-Accessibility path, and hands the user into the actual
/// searchable panel instead of ending on instructional prose.
final class ActivationFunnelUITests: XCTestCase {
    @MainActor
    func testOnboardingHandsOffToRealPanel() throws {
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-regular-activation-for-ui-tests", "-use-in-process-status-item",
            "-force-ephemeral-store", "-force-capture-active",
            "-force-pasteboard-access-allowed", "-disable-screen-share-auto-pause",
            // No `-open-welcome-on-launch`: the fresh defaults suite below makes
            // this a real first run, so onboarding opening at all is part of what
            // this test proves.
            "-seed-sample-clips", "-ui-test-accessibility-trusted", "NO",
            "-ui-test-defaults-suite", "com.johnny4young.gancho.uitests.\(UUID().uuidString)",
            "-telemetry-consent", "notAsked", "-AppleLanguages", "(en)"
        ]
        app.launch()
        defer { app.terminate() }

        let continueButton = app.buttons["onboarding-continue"].firstMatch
        XCTAssertTrue(continueButton.waitForExistence(timeout: 8))
        let dots = app.descendants(matching: .any)["onboarding-page-dots"].firstMatch
        XCTAssertEqual(dots.label, "Step 1 of 4")
        XCTAssertTrue(app.buttons["onboarding-open-privacy-center"].firstMatch.exists)
        let backButton = app.buttons["onboarding-back"].firstMatch
        XCTAssertFalse(backButton.exists, "The first step has no previous step")
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        continueButton.click()

        // Not granted: the primary opens System Settings and "Skip for now" moves on.
        let accessibilitySettings = app.buttons["open-accessibility-settings"].firstMatch
        XCTAssertTrue(accessibilitySettings.waitForExistence(timeout: 5))
        XCTAssertFalse(continueButton.exists)
        let skipForNow = app.buttons["onboarding-skip-for-now"].firstMatch
        XCTAssertTrue(skipForNow.exists && !app.buttons["onboarding-skip"].firstMatch.exists)
        skipForNow.click()

        let panelKeys = app.descendants(matching: .any)["onboarding-shortcut-keys-panel"]
            .firstMatch
        XCTAssertTrue(panelKeys.waitForExistence(timeout: 5))
        XCTAssertEqual(dots.label, "Step 3 of 4")
        continueButton.click()

        let importer = app.buttons["onboarding-open-migration-importer"].firstMatch
        XCTAssertTrue(importer.waitForExistence(timeout: 5), "The first-copy step must render")
        XCTAssertTrue(
            continueButton.label.hasPrefix("Open Gancho panel"),
            "The last step ends in the real panel: \(continueButton.label)")
        XCTAssertTrue(backButton.exists)
        backButton.click()
        XCTAssertTrue(panelKeys.waitForExistence(timeout: 5))
        backButton.click()
        XCTAssertTrue(accessibilitySettings.waitForExistence(timeout: 5))
        backButton.click()
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5))
        XCTAssertFalse(backButton.exists)
        XCTAssertTrue(app.buttons["onboarding-skip"].firstMatch.exists)
        continueButton.click()
        XCTAssertTrue(skipForNow.waitForExistence(timeout: 5))
        skipForNow.click()
        XCTAssertTrue(continueButton.waitForExistence(timeout: 5))
        continueButton.click()
        XCTAssertTrue(importer.waitForExistence(timeout: 5))

        try keepRender(
            of: "Welcome to Gancho", in: app, named: "macOS activation onboarding handoff")

        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        continueButton.click()
        XCTAssertTrue(
            app.textFields["search-field"].firstMatch.waitForExistence(timeout: 8),
            "Completing onboarding must open the real searchable panel")
    }
}

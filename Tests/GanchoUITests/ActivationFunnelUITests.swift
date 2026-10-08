import Foundation
import XCTest

/// First-value smoke over the real macOS shell: onboarding keeps its three
/// screens, explains the no-Accessibility recovery, and hands the user into the
/// actual searchable panel instead of ending on instructional prose.
final class ActivationFunnelUITests: XCTestCase {
    @MainActor
    func testOnboardingHandsOffToRealPanel() {
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-regular-activation-for-ui-tests", "-use-in-process-status-item",
            "-force-ephemeral-store", "-force-capture-active",
            "-force-pasteboard-access-allowed", "-disable-screen-share-auto-pause",
            // No `-open-welcome-on-launch`: the fresh defaults suite below makes
            // this a real first run, so onboarding opening at all is part of what
            // this test proves.
            "-seed-sample-clips",
            "-ui-test-defaults-suite", "com.johnny4young.gancho.uitests.\(UUID().uuidString)",
            "-telemetry-consent", "notAsked", "-AppleLanguages", "(en)"
        ]
        app.launch()
        defer { app.terminate() }

        let continueButton = app.buttons["onboarding-continue"].firstMatch
        XCTAssertTrue(continueButton.waitForExistence(timeout: 8))
        let backButton = app.buttons["onboarding-back"].firstMatch
        XCTAssertFalse(backButton.exists, "The first step has no previous step")
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        continueButton.click()
        let accessibilitySettings = app.buttons["open-accessibility-settings"].firstMatch
        let permissionGranted = app.staticTexts["Permission granted"].firstMatch
        XCTAssertTrue(
            accessibilitySettings.waitForExistence(timeout: 5)
                || permissionGranted.waitForExistence(timeout: 5),
            "The Accessibility onboarding step must finish rendering")
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        continueButton.click()

        let copyFallback = app.staticTexts[
            "If direct paste is unavailable, Gancho copies the clip so you can press ⌘V."
        ].firstMatch
        XCTAssertTrue(
            copyFallback.waitForExistence(timeout: 5),
            "The activation handoff step must finish rendering")
        XCTAssertEqual(continueButton.label, "Open Gancho panel")
        XCTAssertTrue(backButton.exists)
        backButton.click()
        XCTAssertTrue(
            accessibilitySettings.waitForExistence(timeout: 5)
                || permissionGranted.waitForExistence(timeout: 5))
        backButton.click()
        XCTAssertTrue(
            app.buttons["onboarding-open-migration-importer"].firstMatch
                .waitForExistence(timeout: 5))
        XCTAssertFalse(backButton.exists)
        XCTAssertTrue(app.buttons["onboarding-skip"].firstMatch.exists)
        continueButton.click()
        XCTAssertTrue(backButton.waitForExistence(timeout: 5))
        continueButton.click()
        XCTAssertTrue(copyFallback.waitForExistence(timeout: 5))

        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = "macOS activation onboarding handoff"
        attachment.lifetime = .keepAlways
        add(attachment)

        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        continueButton.click()
        XCTAssertTrue(
            app.textFields["search-field"].firstMatch.waitForExistence(timeout: 8),
            "Completing onboarding must open the real searchable panel")
    }
}

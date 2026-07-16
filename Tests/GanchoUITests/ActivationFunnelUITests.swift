import Foundation
import XCTest

/// First-value smoke over the real macOS shell: onboarding keeps its three
/// screens, explains the no-Accessibility recovery, and hands the user into the
/// actual searchable panel instead of ending on instructional prose.
final class ActivationFunnelUITests: XCTestCase {
    @MainActor
    func testOnboardingHandsOffToRealPanel() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-regular-activation-for-ui-tests", "-use-in-process-status-item",
            "-force-ephemeral-store", "-force-capture-active",
            "-force-pasteboard-access-allowed", "-disable-screen-share-auto-pause",
            "-open-welcome-on-launch", "-seed-sample-clips",
            "-ui-test-defaults-suite", "com.johnny4young.gancho.uitests.\(UUID().uuidString)",
            "-telemetry-consent", "notAsked", "-AppleLanguages", "(en)"
        ]
        app.launch()
        defer { app.terminate() }

        let continueButton = app.buttons["onboarding-continue"].firstMatch
        XCTAssertTrue(continueButton.waitForExistence(timeout: 8))
        continueButton.click()
        XCTAssertTrue(
            app.buttons["open-accessibility-settings"].firstMatch.exists
                || app.staticTexts["Permission granted"].firstMatch.exists)
        continueButton.click()

        XCTAssertEqual(continueButton.label, "Open Gancho panel")
        XCTAssertTrue(
            app.staticTexts[
                "If direct paste is unavailable, Gancho copies the clip so you can press ⌘V."
            ].firstMatch.waitForExistence(timeout: 3))

        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        attachment.name = "macOS activation onboarding handoff"
        attachment.lifetime = .keepAlways
        add(attachment)

        continueButton.click()
        XCTAssertTrue(
            app.textFields["search-field"].firstMatch.waitForExistence(timeout: 8),
            "Completing onboarding must open the real searchable panel")
    }
}

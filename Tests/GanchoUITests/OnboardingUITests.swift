import Foundation
import XCTest

/// The welcome's links and in-place controls: the promise opens the Privacy
/// Center, and an unset shortcut swaps its "Not set" for the recorder.
final class OnboardingUITests: XCTestCase {
    @MainActor
    func testPromiseOpensThePrivacyCenter() throws {
        let app = launch(step: 0)
        defer { app.terminate() }
        let link = app.buttons["onboarding-open-privacy-center"].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 8))
        let lifetime = NSPredicate(
            format: "label CONTAINS %@ OR value CONTAINS %@", "after 10 minutes",
            "after 10 minutes")
        XCTAssertTrue(
            app.descendants(matching: .any).matching(lifetime).firstMatch.exists,
            "The promise names the configured secret lifetime")
        link.click()
        XCTAssertTrue(app.windows["Privacy Center"].firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testUnsetShortcutSwapsInTheRecorder() throws {
        let app = launch(step: 2)
        defer { app.terminate() }
        let keys = app.descendants(matching: .any)["onboarding-shortcut-keys-stack"].firstMatch
        XCTAssertTrue(keys.waitForExistence(timeout: 8))
        let set = app.buttons["onboarding-shortcut-change-stack"].firstMatch
        // Recorded shortcuts live outside the per-test defaults suite.
        XCTAssertTrue(["Set…", "Change…"].contains(set.label), set.label)
        set.click()
        XCTAssertTrue(
            app.descendants(matching: .any)["onboarding-shortcut-recorder-stack"].firstMatch
                .waitForExistence(timeout: 5))
        XCTAssertFalse(keys.exists)
        app.buttons["onboarding-shortcut-done-stack"].firstMatch.click()
        XCTAssertTrue(keys.waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.descendants(matching: .any)["onboarding-shortcut-keys-panel"].firstMatch.exists)
    }

    @MainActor private func launch(step: Int) -> XCUIApplication {
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-regular-activation-for-ui-tests", "-use-in-process-status-item",
            "-force-ephemeral-store", "-start-capture-paused", "-open-welcome-on-launch",
            "-ui-test-onboarding-step", "\(step)",
            "-ui-test-defaults-suite", "com.johnny4young.gancho.uitests.\(UUID().uuidString)",
            "-telemetry-consent", "notAsked", "-AppleLanguages", "(en)"
        ]
        app.launch()
        app.activate()
        return app
    }
}

import Foundation
import XCTest

/// The welcome's links and in-place controls: the promise opens the Privacy
/// Center, an unset shortcut swaps its "Not set" for the recorder, and a
/// reopened welcome starts over.
final class OnboardingUITests: XCTestCase {
    private static let nonce = "onboarding-ui-test"

    @MainActor
    func testPromiseOpensThePrivacyCenter() throws {
        let app = try launch(step: 0)
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
        let app = try launch(step: 2)
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

    @MainActor
    func testReopenedWelcomeStartsAtThePromise() throws {
        let app = try launch(step: nil)
        defer { app.terminate() }
        let dots = app.descendants(matching: .any)["onboarding-page-dots"].firstMatch
        XCTAssertTrue(dots.waitForExistence(timeout: 8))
        app.buttons["onboarding-continue"].firstMatch.click()
        let skipForNow = app.buttons["onboarding-skip-for-now"].firstMatch
        XCTAssertTrue(skipForNow.waitForExistence(timeout: 5))
        skipForNow.click()
        let skip = app.buttons["onboarding-skip"].firstMatch
        XCTAssertTrue(skip.waitForExistence(timeout: 5))
        XCTAssertEqual(dots.label, "Step 3 of 4")
        skip.click()
        XCTAssertTrue(dots.waitForNonExistence(timeout: 5))

        // The helper's "Welcome to Gancho" command, as the menu sends it.
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.johnny4young.gancho.menu-bar-command.welcome"),
            object: Self.nonce, userInfo: nil, options: [.deliverImmediately])
        XCTAssertTrue(dots.waitForExistence(timeout: 5))
        XCTAssertEqual(dots.label, "Step 1 of 4", "a reopened welcome starts over")
    }

    @MainActor private func launch(step: Int?) throws -> XCUIApplication {
        let app = GanchoUITestApplication()
        app.launchArguments =
            [
                "-regular-activation-for-ui-tests", "-use-in-process-status-item",
                "-force-ephemeral-store", "-start-capture-paused", "-open-welcome-on-launch",
                "-ui-test-accessibility-trusted", "NO", "-command-nonce", Self.nonce,
                "-ui-test-defaults-suite", "com.johnny4young.gancho.uitests.\(UUID().uuidString)",
                "-telemetry-consent", "notAsked", "-AppleLanguages", "(en)"
            ] + (step.map { ["-ui-test-onboarding-step", "\($0)"] } ?? [])
        app.launch()
        app.activate()
        // Clicks are screen points: never send them while another app is in front.
        guard app.wait(for: .runningForeground, timeout: 5) else {
            app.terminate()
            throw XCTSkip("Gancho did not come to the foreground")
        }
        return app
    }
}

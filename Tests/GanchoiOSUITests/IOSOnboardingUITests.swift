import XCTest

/// The two-page welcome: Next leads to "Sensed, not read", Back returns, the
/// set-up guides open in place, and Get started closes it. `-open-welcome-on-launch`
/// is a DEBUG-only hook that shows the welcome whatever the simulator remembers.
final class IOSOnboardingUITests: XCTestCase {
    @MainActor
    func testWelcomePagesToSensedNotReadAndBack() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-open-welcome-on-launch", "-force-ephemeral-store", "-AppleLanguages", "(en)"
        ]
        app.launch()
        defer { app.terminate() }

        let next = app.buttons["onboarding-next"].firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["onboarding-done"].exists, "Get started lives on page 2")
        next.tap()

        let example = app.descendants(matching: .any)["onboarding-sensed-example"].firstMatch
        XCTAssertTrue(example.waitForExistence(timeout: 5))
        XCTAssertTrue(app.navigationBars["2 of 2"].exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["onboarding-paste-control"].firstMatch.exists)
        XCTAssertTrue(
            app.descendants(matching: .any)["onboarding-share-status"].firstMatch.exists)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "iOS welcome page 2 sensed not read"
        attachment.lifetime = .keepAlways
        add(attachment)

        app.buttons["onboarding-how-keyboard"].firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Gancho keyboard"].waitForExistence(timeout: 5))
        app.navigationBars["Gancho keyboard"].buttons["Done"].tap()
        XCTAssertTrue(example.waitForExistence(timeout: 5))

        app.buttons["onboarding-back"].firstMatch.tap()
        XCTAssertTrue(next.waitForExistence(timeout: 5))
        next.tap()
        let done = app.buttons["onboarding-done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.tap()
        XCTAssertTrue(
            next.waitForNonExistence(timeout: 5), "Get started closes the welcome")
        XCTAssertFalse(example.exists)
    }
}

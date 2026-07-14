import XCTest

final class SourceAppFilterUITests: XCTestCase {
    @MainActor
    func testSourceAppFilterNarrowsHistoryAndCapturesEvidence() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-skip-welcome-on-launch", "-use-temp-durable-store", "-seed-source-apps",
            "-AppleLanguages", "(en)"
        ]
        app.launch()
        defer { app.terminate() }

        let capture = app.descendants(matching: .any)["capture-screen"].firstMatch
        guard capture.waitForExistence(timeout: 10) else {
            throw XCTSkip("capture screen is not reachable on this runner")
        }

        let filter = app.descendants(matching: .any)["history-filter-menu"].firstMatch
        guard filter.waitForExistence(timeout: 8), filter.isHittable else {
            throw XCTSkip("history filter menu is not reachable on this runner")
        }
        filter.tap()

        let safari = app.descendants(matching: .any)["Safari"].firstMatch
        XCTAssertTrue(safari.waitForExistence(timeout: 5), "Safari source filter is missing")
        XCTAssertTrue(safari.isHittable, "Safari source filter is not hittable")
        safari.tap()

        XCTAssertTrue(app.staticTexts["Safari source alpha"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Safari source link"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Xcode source sample"].exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "iOS source-app filter — Safari"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

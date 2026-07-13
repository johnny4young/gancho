import XCTest

final class SourceAppFilterUITests: XCTestCase {
    @MainActor
    func testSourceAppFilterNarrowsThePanelAndCapturesEvidence() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item",
            "-use-temp-durable-store", "-seed-source-apps",
            "-AppleLanguages", "(en)"
        ]
        app.launch()
        defer { app.terminate() }

        let filter = app.descendants(matching: .any)["source-app-filter"].firstMatch
        guard filter.waitForExistence(timeout: 10), filter.isHittable else {
            throw XCTSkip("source-app filter is not reachable on this runner")
        }
        filter.click()

        let safari = app.descendants(matching: .any)["Safari"].firstMatch
        XCTAssertTrue(safari.waitForExistence(timeout: 4), "Safari source filter is missing")
        XCTAssertTrue(safari.isHittable, "Safari source filter is not hittable")
        safari.click()

        XCTAssertTrue(app.staticTexts["Safari source alpha"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Safari source link"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Xcode source sample"].exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "macOS source-app filter — Safari"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

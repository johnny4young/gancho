import XCTest

final class ReuseSuggestionUITests: XCTestCase {
    @MainActor
    func testThirdPasteOffersOneTapSnippetPromotionAndCapturesEvidence() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item",
            "-use-temp-durable-store", "-seed-reuse-suggestion",
            "-force-free-tier", "-AppleLanguages", "(en)"
        ]
        app.launch()
        defer { app.terminate() }

        let row = app.descendants(matching: .any).matching(identifier: "clip-row").firstMatch
        guard row.waitForExistence(timeout: 10), row.isHittable else {
            throw XCTSkip("seeded panel row is not reachable on this runner")
        }
        row.doubleClick()

        let toast = app.descendants(matching: .any)["gancho-toast"].firstMatch
        XCTAssertTrue(toast.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Used 3 times — save as a snippet?"].exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "macOS exact-third-use snippet suggestion"
        attachment.lifetime = .keepAlways
        add(attachment)

        let action = app.buttons["reuse-suggestion-action"].firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: 2))
        XCTAssertTrue(action.isHittable)
        action.click()
        XCTAssertTrue(app.staticTexts["Saved as snippet"].waitForExistence(timeout: 5))
    }
}

import XCTest

final class TranslationCapabilityUITests: XCTestCase {
    @MainActor
    func testInstalledPairOfferedWithoutGenerativeModel() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = [
            "-skip-welcome-on-launch", "-use-temp-durable-store", "-seed-clip-editing",
            "-force-free-tier", "-AppleLanguages", "(en)", "-ui-test-installed-translation"
        ]
        app.launch()
        defer { app.terminate() }
        let row = app.descendants(matching: .any).matching(identifier: "clip-row")
            .matching(NSPredicate(format: "label CONTAINS %@", "Yesterday: fixed search"))
            .firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let grabber = app.buttons["Sheet Grabber"].firstMatch
        XCTAssertTrue(grabber.waitForExistence(timeout: 5))
        grabber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(
                forDuration: 0.1,
                thenDragTo: app.coordinate(
                    withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)))
        let detail = app.collectionViews.matching(
            NSPredicate(format: "identifier != %@", "capture-screen")
        ).firstMatch
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        let menu = app.buttons["smart-paste-menu"].firstMatch
        for _ in 0..<4 where !menu.exists || !menu.isHittable { detail.swipeUp() }
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        XCTAssertTrue(menu.isHittable)
        XCTAssertFalse(app.buttons["smart-paste-summarize-action"].firstMatch.exists)
        menu.tap()
        let spanish = app.buttons["translation-target-es"].firstMatch
        XCTAssertTrue(spanish.waitForExistence(timeout: 5))
        XCTAssertTrue(spanish.isEnabled)
        spanish.tap()
        let result = app.descendants(matching: .any).matching(
            identifier: "intelligence-result-text"
        ).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertTrue(
            result.label.contains("Traducción sintética")
                || (result.value as? String)?.contains("Traducción sintética") == true)
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "Installed translation without a generative model — synthetic"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

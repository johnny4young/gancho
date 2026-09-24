import XCTest

final class OutboundPrivacyUITests: XCTestCase {
    @MainActor
    func testLongPressKeepsIntrinsicContentMaskedAndDoesNotOfferShare() throws {
        let app = launch(seed: "-seed-outbound-privacy")
        defer { app.terminate() }
        let row = app.descendants(matching: .any).matching(identifier: "clip-row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10), "the isolated privacy fixture must appear")
        row.press(forDuration: 1)
        XCTAssertTrue(app.buttons["Copy"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["clip-share-action"].exists)
        let rawPreview = app.descendants(matching: .any).matching(
            NSPredicate(format: "label CONTAINS %@", "synthetic-protected-preview-canary"))
        XCTAssertFalse(
            rawPreview.firstMatch.exists, "the lifted preview and AX labels must stay masked")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "masked-context-preview"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testSafeContextMenuStillOffersSharing() throws {
        let app = launch(seed: "-seed-clip-editing")
        defer { app.terminate() }
        let row = app.descendants(matching: .any).matching(identifier: "clip-row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.press(forDuration: 1)
        XCTAssertTrue(app.buttons["clip-share-action"].firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    private func launch(seed: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-skip-welcome-on-launch", "-use-temp-durable-store", seed,
            "-force-free-tier", "-AppleLanguages", "(en)"
        ]
        app.launch()
        return app
    }
}

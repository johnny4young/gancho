import XCTest

final class ClipTitleEditingUITests: XCTestCase {
    @MainActor
    func testUntitledClipCanBeNamedInlineAndCapturesEvidence() throws {
        let app = try launchSeededApp()
        defer { app.terminate() }

        let row = app.descendants(matching: .any).matching(identifier: "clip-row").firstMatch
        row.tap()
        // At the medium detent a minimized software keyboard reappears on the
        // Save tap and expands the sheet mid-tap, so edit at the large detent.
        let grabber = app.buttons["Sheet Grabber"].firstMatch
        XCTAssertTrue(grabber.waitForExistence(timeout: 5))
        grabber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(
                forDuration: 0.1,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)))
        let expanded = expectation(
            for: NSPredicate(format: "value == %@", "Expanded"), evaluatedWith: grabber)
        wait(for: [expanded], timeout: 5)
        let edit = app.buttons["detail-edit-title"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()

        let field = app.textFields["detail-title-field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        field.tap()
        let title = "Team standup"
        for character in title { field.typeText(String(character)) }
        XCTAssertEqual(
            field.value as? String, title,
            "The complete synthetic title must reach the field before Save")
        app.buttons["detail-save-title"].firstMatch.tap()

        XCTAssertTrue(app.staticTexts["Team standup"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "iOS inline clip title editing"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func launchSeededApp() throws -> XCUIApplication {
        let app = XCUIApplication()
        for _ in 0..<2 {
            app.terminate()
            app.launchArguments = [
                "-skip-welcome-on-launch", "-use-temp-durable-store", "-seed-clip-editing",
                "-force-free-tier", "-AppleLanguages", "(en)"
            ]
            app.launch()
            let row = app.descendants(matching: .any).matching(identifier: "clip-row").firstMatch
            if row.waitForExistence(timeout: 8) { return app }
        }
        return try XCTUnwrap(
            nil as XCUIApplication?,
            "the isolated clip-editing fixture did not become available after one retry")
    }
}

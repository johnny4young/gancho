import XCTest

final class ClipTitleEditingUITests: XCTestCase {
    @MainActor
    func testUntitledClipCanBeNamedInlineAndCapturesEvidence() throws {
        let app = try launchSeededApp()
        defer { app.terminate() }

        let row = app.descendants(matching: .any).matching(identifier: "clip-row").firstMatch
        row.tap()
        let edit = app.buttons["detail-edit-title"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()

        let field = app.textFields["detail-title-field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        field.tap()
        field.typeText("Team standup")
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

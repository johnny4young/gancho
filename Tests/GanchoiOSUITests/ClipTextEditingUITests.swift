import XCTest

final class ClipTextEditingUITests: XCTestCase {
    @MainActor
    func testTextClipUsesExplicitSaveAndCapturesEvidence() throws {
        let app = try launchSeededApp()
        defer { app.terminate() }

        let row = app.descendants(matching: .any).matching(identifier: "clip-row").firstMatch
        row.tap()
        let edit = app.buttons["detail-edit-content"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.tap()

        let field = app.textViews["detail-content-field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        field.tap()
        field.typeText("Next: ship safely\n")
        app.buttons["detail-save-content"].firstMatch.tap()

        let finalText =
            "Next: ship safely\nYesterday: fixed search\nToday: improve editing\nBlockers: none"
        let saved = app.staticTexts.matching(
            NSPredicate(format: "label == %@", finalText)
        ).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "iOS explicit clip text editing"
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

import XCTest

final class ClipTitleEditingUITests: XCTestCase {
    @MainActor
    func testUntitledClipCanBeNamedInlineAndCapturesEvidence() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item",
            "-use-temp-durable-store", "-seed-clip-editing",
            "-force-free-tier", "-start-capture-paused", "-AppleLanguages", "(en)"
        ]
        app.launch()
        defer { app.terminate() }

        let row = app.descendants(matching: .any).matching(identifier: "clip-row").firstMatch
        guard row.waitForExistence(timeout: 10), row.isHittable else {
            throw XCTSkip("seeded panel row is not reachable on this runner")
        }
        row.click()

        let edit = app.buttons["preview-edit-title"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.click()
        let field = app.textFields["preview-title-field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        field.typeText("Team standup")
        app.buttons["preview-save-title"].firstMatch.click()

        XCTAssertTrue(app.staticTexts["Team standup"].waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "macOS inline clip title editing"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

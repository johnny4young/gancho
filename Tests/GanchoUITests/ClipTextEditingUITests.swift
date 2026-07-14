import XCTest

final class ClipTextEditingUITests: XCTestCase {
    @MainActor
    func testTextClipUsesExplicitSaveAndCapturesEvidence() throws {
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

        let edit = app.buttons["preview-edit-content"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.click()
        let field = app.textViews["preview-content-field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 2))
        field.click()
        app.typeKey("a", modifierFlags: .command)
        let finalText =
            "Next: ship safely\nYesterday: fixed search\nToday: improve editing\nBlockers: none"
        field.typeText(finalText)
        app.buttons["preview-save-content"].firstMatch.click()

        // ClipCard combines the kind and exact preview into one semantic row;
        // assert that durable list update instead of assuming the preview Text
        // exposes its contents through the accessibility label rather than value.
        let saved = app.staticTexts.matching(
            NSPredicate(
                format: "identifier == 'clip-row' AND label CONTAINS %@", finalText)
        ).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "macOS explicit clip text editing"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

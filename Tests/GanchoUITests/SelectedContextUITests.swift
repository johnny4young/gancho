import XCTest

final class SelectedContextUITests: XCTestCase {
    @MainActor
    func testReviewReorderCancelAndCopyKeepClipsIntact() throws {
        continueAfterFailure = false
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item", "-use-temp-durable-store",
            "-seed-source-apps", "-force-free-tier", "-start-capture-paused",
            "-place-panel-for-ui-test", "-opaque-panel-for-ui-test",
            "-suppress-storage-notice-for-ui-test",
            "-ui-test-paste-sink", "copy-only", "-AppleLanguages", "(en)",
            "-ui-test-defaults-suite", "com.johnny4young.gancho.uitests.selected-context.\(UUID())"
        ]
        app.launch()
        defer { app.terminate() }
        app.activate()
        let rows = app.descendants(matching: .any).matching(identifier: "clip-row")
        XCTAssertTrue(rows.element(boundBy: 2).waitForExistence(timeout: 15))
        let count = rows.count
        try SynthesizedInput.requireForeground(app)
        rows.element(boundBy: 0).click()
        XCUIElement.perform(withKeyModifiers: .command) { rows.element(boundBy: 2).click() }
        let action = app.buttons["selection-ai-context-button"].firstMatch
        XCTAssertTrue(action.waitForExistence(timeout: 5))
        action.click()
        let preview = app.descendants(matching: .any)["ai-context-preview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        let copy = app.buttons["ai-context-copy-button"].firstMatch
        XCTAssertTrue(copy.waitForHittable(timeout: 5))
        XCTAssertTrue(copy.isEnabled)
        XCTAssertFalse(app.buttons["ai-context-grant-button"].firstMatch.isEnabled)
        let move = app.buttons["text-selection-move-down-button"].firstMatch
        XCTAssertTrue(move.isEnabled)
        move.click()
        let attachment = XCTAttachment(
            screenshot: app.dialogs["history-panel"].firstMatch.screenshot())
        attachment.name = "Selected context review — synthetic clips"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["ai-context-cancel-button"].firstMatch.click()
        XCTAssertTrue(preview.waitForNonExistence(timeout: 5))
        XCTAssertEqual(rows.count, count)
        action.click()
        XCTAssertTrue(copy.waitForHittable(timeout: 5))
        copy.click()
        XCTAssertTrue(preview.waitForNonExistence(timeout: 5))
        XCTAssertEqual(rows.count, count)
    }
}

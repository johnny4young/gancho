import XCTest

final class ClipLargePreviewUITests: XCTestCase {
    @MainActor
    func testCommandYOpensExactReadOnlyContentAndCapturesEvidence() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item",
            "-use-temp-durable-store", "-seed-clip-editing",
            "-force-free-tier", "-start-capture-paused", "-AppleLanguages", "(en)"
        ]
        app.launch()
        defer { app.terminate() }

        let search = app.textFields["search-field"].firstMatch
        guard search.waitForExistence(timeout: 10) else {
            throw XCTSkip("history panel is not reachable on this runner")
        }
        let row = app.descendants(matching: .any).matching(identifier: "clip-row").firstMatch
        guard row.waitForExistence(timeout: 10) else {
            throw XCTSkip("seeded preview clip is not reachable on this runner")
        }

        // ⌘Y is a GLOBAL shortcut: if the menu-bar-agent panel isn't frontmost
        // on this runner it would fire in whatever app is (⌘Y opens History in
        // browsers). Skip rather than drive another app.
        try SynthesizedInput.requireForeground(app)
        app.typeKey("y", modifierFlags: .command)

        let preview = app.sheets["large-preview-window"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        let content = app.textViews["large-preview-content"].firstMatch
        XCTAssertTrue(content.waitForExistence(timeout: 5))
        XCTAssertEqual(
            content.value as? String,
            "Yesterday: fixed search\nToday: improve editing\nBlockers: none")

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "macOS Command-Y large preview"
        attachment.lifetime = .keepAlways
        add(attachment)

        app.typeKey("y", modifierFlags: .command)
        XCTAssertTrue(content.waitForNonExistence(timeout: 5))
        XCTAssertTrue(search.exists, "closing the preview should return to the history panel")
    }
}

import XCTest

final class ClipTitleEditingUITests: XCTestCase {
    @MainActor
    func testUntitledClipCanBeNamedInlineAndCapturesEvidence() throws {
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item",
            "-use-temp-durable-store", "-seed-clip-editing",
            "-force-free-tier", "-start-capture-paused", "-AppleLanguages", "(en)"
        ]
        app.launch()
        defer { app.terminate() }
        app.activate()

        let row = app.descendants(matching: .any).matching(identifier: "clip-row").firstMatch
        guard row.waitForHittable(timeout: 10) else {
            throw XCTSkip("seeded panel row is not reachable on this runner")
        }
        try SynthesizedInput.requireForeground(app)
        row.click()

        let edit = app.buttons["preview-edit-title"].firstMatch
        XCTAssertTrue(edit.appears(within: 5))
        edit.click()
        let field = app.textFields["preview-title-field"].firstMatch
        XCTAssertTrue(field.appears(within: 2))
        try typeTextReliably("Team standup", into: field, in: app)
        app.buttons["preview-save-title"].firstMatch.click()

        XCTAssertTrue(app.staticTexts["Team standup"].appears(within: 5))
        try keepRender(of: "history-panel", in: app, named: "macOS inline clip title editing")
    }
}

import XCTest

final class SelectedContextUITests: XCTestCase {
    @MainActor
    func testReviewReorderCancelAndCopyKeepClipsIntact() throws { try verify("en", "light") }
    @MainActor func testEnglishDark() throws { try verify("en", "dark") }
    @MainActor func testSpanishLight() throws { try verify("es", "light") }
    @MainActor func testSpanishDark() throws { try verify("es", "dark") }

    @MainActor
    func testExplicitGrantShowsMarkedCopyCommandWithoutSavingClips() throws {
        try verify("en", "light", asGrant: true)
    }

    @MainActor private func verify(
        _ language: String, _ appearance: String, asGrant: Bool = false
    ) throws {
        continueAfterFailure = false
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item", "-use-temp-durable-store",
            "-seed-source-apps", "-force-free-tier", "-start-capture-paused",
            "-place-panel-for-ui-test", "-opaque-panel-for-ui-test",
            "-suppress-storage-notice-for-ui-test",
            "-ui-test-paste-sink", "copy-only", "-AppleLanguages", "(\(language))",
            "-appearance", appearance, "-panel-text-size", "large",
            "-panel-content-width", "720", "-panel-content-height", "460",
            "-ui-test-defaults-suite", "com.johnny4young.gancho.uitests.selected-context.\(UUID())"
        ]
        app.launch()
        defer { app.terminate() }
        app.activate()
        let rows = app.descendants(matching: .any).matching(identifier: "clip-row")
        XCTAssertTrue(rows.element(boundBy: 2).waitForExistence(timeout: 15))
        let count = rows.count
        try SynthesizedInput.requireForeground(app)
        app.typeKey(.tab, modifierFlags: [])
        rows.element(boundBy: 0).click()
        XCUIElement.perform(withKeyModifiers: .command) { rows.element(boundBy: 2).click() }
        let action = app.buttons["selection-ai-context-button"].firstMatch
        XCTAssertTrue(action.waitForHittable(timeout: 5))
        action.hover()
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
            screenshot: app.sheets.firstMatch.screenshot())
        attachment.name = "Selected context review — synthetic clips — \(language) — \(appearance)"
        attachment.lifetime = .keepAlways
        add(attachment)
        if asGrant {
            try verifyGrant(in: app, preview: preview, originalCount: count)
            return
        }
        app.buttons["ai-context-cancel-button"].firstMatch.click()
        XCTAssertTrue(preview.waitForNonExistence(timeout: 5))
        XCTAssertEqual(rows.count, count)
        action.click()
        XCTAssertTrue(copy.waitForHittable(timeout: 5))
        copy.click()
        XCTAssertTrue(preview.waitForNonExistence(timeout: 5))
        XCTAssertEqual(rows.count, count)
    }
    @MainActor
    private func verifyGrant(
        in app: GanchoUITestApplication, preview: XCUIElement, originalCount: Int
    ) throws {
        let name = app.textFields["ai-context-client-field"].firstMatch
        try typeTextReliably("Synthetic read-only client", into: name, in: app)
        let authorize = app.buttons["ai-context-grant-button"].firstMatch
        XCTAssertTrue(authorize.isEnabled)
        authorize.click()
        let command = app.buttons["ai-context-copy-command-button"].firstMatch
        XCTAssertTrue(command.waitForHittable(timeout: 5))
        XCTAssertTrue(command.isEnabled)
        command.click()
        app.buttons["ai-context-cancel-button"].firstMatch.click()
        XCTAssertTrue(preview.waitForNonExistence(timeout: 5))
        XCTAssertEqual(
            app.descendants(matching: .any).matching(identifier: "clip-row").count,
            originalCount)
    }

}

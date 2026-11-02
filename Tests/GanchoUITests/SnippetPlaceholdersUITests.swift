import XCTest

/// Smart placeholders: chips that write them in the editor, and a fill sheet
/// that asks for fields and dates and never reads the clipboard to preview.
final class SnippetPlaceholdersUITests: XCTestCase {
    @MainActor
    private func launch(
        appearance: String = "light"
    ) -> (app: XCUIApplication, token: String) {
        continueAfterFailure = false
        let token = UUID().uuidString
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item", "-use-temp-durable-store",
            "-seed-snippets", "-seed-snippet-placeholders", "-force-free-tier",
            "-start-capture-paused", "-isolate-ui-test-system-clipboard",
            "-suppress-storage-notice-for-ui-test", "-ui-test-paste-sink", "copy-only",
            "-opaque-panel-for-ui-test", "-place-panel-for-ui-test", "-place-library-for-ui-test",
            "-AppleLanguages", "(en)", "-appearance", appearance, "-telemetry-consent", "disabled",
            "-command-nonce", token, "-ui-test-defaults-suite",
            "com.johnny4young.gancho.uitests.placeholders.\(UUID().uuidString)"
        ]
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 5)
        return (app, token)
    }

    @MainActor
    private func openFillSheet(_ app: XCUIApplication) throws -> XCUIElement {
        let search = app.textFields["search-field"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        try SynthesizedInput.requireForeground(app)
        search.click()
        search.typeText("hi")
        let banner = app.buttons["snippet-insert-banner"].firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 5))
        banner.click()
        let sheet = app.sheets.firstMatch
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        return sheet
    }

    @MainActor
    private func openEditor(
        _ app: XCUIApplication, token: String
    ) throws -> (library: XCUIElement, editor: XCUIElement) {
        XCTAssertTrue(app.textFields["search-field"].firstMatch.waitForExistence(timeout: 15))
        GanchoUITestCommands.post("library", token: token)
        let library = app.windows["Library"].firstMatch
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        let row = library.staticTexts["Seed sign-off"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        try SynthesizedInput.requireForeground(app)
        row.click()
        let editor = library.textViews["snippet-editor"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        return (library, editor)
    }

    @MainActor
    private func waitForValue(of editor: XCUIElement, containing text: String) -> Bool {
        let deadline = Date().addingTimeInterval(5)
        repeat {
            if (editor.value as? String)?.contains(text) == true { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline
        return false
    }

    @MainActor
    private func chip(_ id: String, in library: XCUIElement) -> XCUIElement {
        library.buttons["insert-placeholder-\(id)"].firstMatch
    }

    /// The field asks, the date offers a picker, and the preview shows the date
    /// while leaving the clipboard and the cursor unread.
    @MainActor
    func testSheetAsksForFieldsAndDatesAndPreviewsWithoutTheClipboard() throws {
        let (app, _) = launch()
        defer { app.terminate() }
        let sheet = try openFillSheet(app)
        XCTAssertTrue(sheet.textFields["fill-field-name"].firstMatch.exists)
        XCTAssertFalse(
            sheet.textFields["fill-field-clipboard"].firstMatch.exists, "not a field to type")
        XCTAssertFalse(sheet.textFields["fill-field-cursor"].firstMatch.exists)
        let picker = sheet.descendants(matching: .any)["fill-date-2"].firstMatch
        XCTAssertTrue(picker.exists)

        let preview = sheet.staticTexts.matching(
            NSPredicate(format: "value CONTAINS %@", "{clipboard | trim}")
        ).firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 3))
        let shown = (preview.value as? String) ?? ""
        XCTAssertTrue(shown.contains("{cursor}"), shown)
        XCTAssertFalse(shown.contains("{date"), "the date is filled: \(shown)")
        try keepRender(of: "@sheet", in: app, named: "Snippet fill sheet")

        sheet.buttons["fill-insert"].firstMatch.click()
        XCTAssertTrue(sheet.waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testChipsWriteAtTheCaretAndModifiersFollowThePlaceholder() throws {
        let (app, token) = launch()
        defer { app.terminate() }
        let (library, editor) = try openEditor(app, token: token)
        for id in ["field", "clipboard", "clipboard-offset", "date", "cursor"] {
            XCTAssertTrue(chip(id, in: library).exists, id)
        }
        editor.click()
        app.typeKey(.downArrow, modifierFlags: .command)
        XCTAssertFalse(chip("trim", in: library).isEnabled, "no placeholder at the caret")

        chip("date", in: library).click()
        XCTAssertTrue(waitForValue(of: editor, containing: "{date}"))
        XCTAssertTrue(chip("uppercase", in: library).isEnabled, "right after a placeholder")
        chip("uppercase", in: library).click()
        XCTAssertTrue(waitForValue(of: editor, containing: "{date | uppercase}"))

        app.typeKey(.downArrow, modifierFlags: .command)
        chip("clipboard", in: library).click()
        XCTAssertTrue(waitForValue(of: editor, containing: "{date | uppercase}{clipboard}"))
        chip("cursor", in: library).click()
        XCTAssertTrue(waitForValue(of: editor, containing: "{clipboard}{cursor}"))
        XCTAssertFalse(chip("trim", in: library).isEnabled, "the cursor takes no modifier")
        try keepRender(of: "Library", in: app, named: "Snippet editor placeholders")
    }

    @MainActor
    func testFieldChipSelectsTheNameToType() throws {
        let (app, token) = launch()
        defer { app.terminate() }
        let (library, editor) = try openEditor(app, token: token)
        editor.click()
        app.typeKey(.downArrow, modifierFlags: .command)
        chip("field", in: library).click()
        XCTAssertTrue(waitForValue(of: editor, containing: "{field}"))
        app.typeText("client")
        XCTAssertTrue(waitForValue(of: editor, containing: "{client}"))
    }
}

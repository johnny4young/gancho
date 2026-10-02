import XCTest

/// Text typed into a snippet's body survives the Library's own refreshes and
/// is saved when the selection moves on, so neither a background reload nor
/// navigating drops what the user typed; ⌘S saves in place.
final class LibrarySnippetDraftUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    @MainActor
    private func keepCapture(_ window: XCUIElement, name: String) {
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testRemovedSnippetKeepsDraftUntilExplicitRecovery() throws {
        try verifyRecovery(language: "en", appearance: "light")
    }
    @MainActor func testRecoveryEnglishDark() throws {
        try verifyRecovery(language: "en", appearance: "dark")
    }
    @MainActor func testRecoverySpanishLight() throws {
        try verifyRecovery(language: "es", appearance: "light")
    }
    @MainActor func testRecoverySpanishDark() throws {
        try verifyRecovery(language: "es", appearance: "dark")
    }
    @MainActor private func verifyRecovery(language: String, appearance: String) throws {
        continueAfterFailure = false
        let app = GanchoUITestApplication()
        defer { app.terminate() }
        let library = try openLibrary(
            app, extraArguments: ["-ui-test-snippet-deletion"], language: language,
            appearance: appearance)
        library.staticTexts["Seed greeting"].firstMatch.click()
        let editor = library.textViews["snippet-editor"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let original = try XCTUnwrap(editor.value as? String)
        try typeTextReliably(original + " synthetic recovered draft", into: editor, in: app)
        XCTAssertTrue(waitForValue(of: editor, containing: "synthetic recovered draft"))
        library.buttons["snippet-delete-source-button"].firstMatch.click()
        XCTAssertTrue(
            library.buttons["snippet-recover-button"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForValue(of: editor, containing: "synthetic recovered draft"))
        XCTAssertFalse(library.buttons["snippet-save"].firstMatch.isEnabled)
        keepCapture(
            library, name: "Snippet recovery — synthetic draft — \(language) — \(appearance)")

        library.staticTexts["Seed sign-off"].firstMatch.click()
        let cancel = app.buttons["snippet-resolution-cancel-button"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        try SynthesizedInput.requireForeground(app)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForValue(of: editor, containing: "synthetic recovered draft"))

        library.buttons["snippet-recover-button"].firstMatch.click()
        XCTAssertTrue(library.staticTexts["Seed greeting"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitForValue(
                of: library.textViews["snippet-editor"].firstMatch,
                containing: "synthetic recovered draft"))
        XCTAssertFalse(library.buttons["snippet-recover-button"].firstMatch.exists)
        library.staticTexts["Seed sign-off"].firstMatch.click()
        XCTAssertTrue(
            waitForValue(
                of: library.textViews["snippet-editor"].firstMatch,
                containing: "Best regards"))
        library.staticTexts["Seed greeting"].firstMatch.click()
        XCTAssertTrue(
            waitForValue(
                of: library.textViews["snippet-editor"].firstMatch,
                containing: "synthetic recovered draft"))
    }

    @MainActor
    func testDiscardRemovedDraftDoesNotRestoreOriginal() throws {
        let app = GanchoUITestApplication()
        defer { app.terminate() }
        let library = try openLibrary(app, extraArguments: ["-ui-test-snippet-deletion"])
        library.staticTexts["Seed greeting"].firstMatch.click()
        let editor = library.textViews["snippet-editor"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.click()
        XCTAssertTrue(waitForKeyboardFocus(editor))
        editor.typeText("modified ")
        library.buttons["snippet-delete-source-button"].firstMatch.click()
        let discard = library.buttons["snippet-discard-button"].firstMatch
        XCTAssertTrue(discard.waitForExistence(timeout: 5))
        discard.click()
        XCTAssertFalse(library.staticTexts["Seed greeting"].firstMatch.exists)
        library.staticTexts["Seed sign-off"].firstMatch.click()
        XCTAssertTrue(
            waitForValue(
                of: library.textViews["snippet-editor"].firstMatch, containing: "Best regards"))
    }

    @MainActor
    func testFailedNavigationSaveKeepsEditedSnippet() throws {
        let app = GanchoUITestApplication()
        defer { app.terminate() }
        let library = try openLibrary(app, extraArguments: ["-ui-test-snippet-save-failure"])
        library.staticTexts["Seed greeting"].firstMatch.click()
        let editor = library.textViews["snippet-editor"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        editor.click()
        XCTAssertTrue(waitForKeyboardFocus(editor))
        editor.typeText("unsaved ")
        library.staticTexts["Seed sign-off"].firstMatch.click()
        XCTAssertTrue(
            waitForValue(of: library.textViews["snippet-editor"].firstMatch, containing: "unsaved"))
        XCTAssertEqual(
            library.textFields["snippet-title"].firstMatch.value as? String, "Seed greeting")
    }

    @MainActor
    func testTypedBodySurvivesRefreshAndSavesOnSelectionChange() throws {
        continueAfterFailure = false
        let app = GanchoUITestApplication()
        defer { app.terminate() }
        let library = try openLibrary(app)

        let greeting = library.staticTexts["Seed greeting"].firstMatch
        XCTAssertTrue(greeting.waitForExistence(timeout: 10), "the seeded snippets must be listed")
        greeting.click()
        let editor = library.textViews["snippet-editor"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForValue(of: editor, containing: "Hello {name}"))

        editor.click()
        XCTAssertTrue(waitForKeyboardFocus(editor), "the body editor must take focus")
        editor.typeKey(.downArrow, modifierFlags: .command)
        let typed = " plus text typed before the refresh"
        editor.typeText(typed)
        XCTAssertTrue(waitForValue(of: editor, containing: typed))

        // A board created from the sidebar reloads the whole Library, the same
        // path a finished sync takes.
        createBoard(named: "Draft board", in: library, app: app)
        XCTAssertTrue(
            waitForValue(of: editor, containing: typed),
            "a Library refresh must not drop typed text")

        saveTitleWithShortcut(suffix: " saved", in: library)

        // Leaving the snippet saves it; coming back shows the saved text.
        library.staticTexts["Seed sign-off"].firstMatch.click()
        XCTAssertTrue(waitForValue(of: editor, containing: "Best regards"))
        library.staticTexts["Seed greeting saved"].firstMatch.click()
        XCTAssertTrue(
            waitForValue(of: editor, containing: typed),
            "moving to another snippet must save the typed body")
    }

    @MainActor
    private func openLibrary(
        _ app: XCUIApplication, extraArguments: [String] = [], language: String = "en",
        appearance: String? = nil
    ) throws -> XCUIElement {
        let nonce = UUID().uuidString
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item", "-use-temp-durable-store",
            "-seed-snippets", "-force-free-tier", "-start-capture-paused",
            "-AppleLanguages", "(\(language))",
            "-ui-test-defaults-suite",
            "com.johnny4young.gancho.uitests.snippets.\(UUID().uuidString)",
            "-command-nonce", nonce
        ]
        if let appearance { app.launchArguments += ["-appearance", appearance] }
        app.launchArguments += extraArguments
        app.launch()
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertTrue(app.textFields["search-field"].waitForExistence(timeout: 15))
        try SynthesizedInput.requireForeground(app)
        GanchoUITestCommands.post("library", token: nonce)
        let library = app.windows.firstMatch
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        return library
    }

    @MainActor
    private func createBoard(named boardName: String, in library: XCUIElement, app: XCUIApplication)
    {
        library.buttons["board-new"].firstMatch.click()
        let name = app.textFields["Board name"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 5), "the new-board prompt must open")
        name.click()
        XCTAssertTrue(waitForKeyboardFocus(name), "the board name field must take focus")
        name.typeText(boardName)
        // Return is the prompt's default action; a click on its button can land
        // elsewhere on a small display.
        name.typeKey(.return, modifierFlags: [])
        let board = library.staticTexts[boardName].firstMatch
        if !board.waitForExistence(timeout: 3) {
            app.buttons["Create"].firstMatch.click()
        }
        XCTAssertTrue(
            board.waitForExistence(timeout: 5), "creating a board must refresh the sidebar")
    }

    /// ⌘S writes the title without the field losing focus: the sidebar row
    /// takes the new title while the caret stays in place.
    @MainActor
    private func saveTitleWithShortcut(suffix: String, in library: XCUIElement) {
        let title = library.textFields["snippet-title"].firstMatch
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        let before = title.value as? String ?? ""
        title.click()
        XCTAssertTrue(waitForKeyboardFocus(title), "the title field must take focus")
        title.typeKey(.rightArrow, modifierFlags: .command)
        title.typeText(suffix)
        title.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(
            library.staticTexts[before + suffix].firstMatch.waitForExistence(timeout: 5),
            "⌘S must write the title without leaving the field")
        XCTAssertTrue(waitForKeyboardFocus(title), "⌘S must not move focus")
    }

    @MainActor
    private func waitForKeyboardFocus(_ element: XCUIElement, timeout: TimeInterval = 3) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func waitForValue(
        of element: XCUIElement, containing text: String, timeout: TimeInterval = 5
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS %@", text), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}

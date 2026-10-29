import XCTest

/// Native board-name prompts must keep invalid drafts visible and leave the
/// durable store unchanged. All launches use disposable storage and defaults.
final class BoardNameUITests: XCTestCase {
    override func setUp() {
        continueAfterFailure = false
    }

    @MainActor func testLibraryBoardNamesEnglish() throws {
        try exercise(language: "en", library: true)
    }
    @MainActor func testLibraryBoardNamesSpanish() throws {
        try exercise(language: "es", library: true)
    }
    @MainActor func testPanelBoardNamesEnglish() throws {
        try exercise(language: "en", library: false)
    }
    @MainActor func testPanelBoardNamesSpanish() throws {
        try exercise(language: "es", library: false)
    }

    @MainActor func testCreateFromClipEnglish() throws { try createFromClip(language: "en") }
    @MainActor func testCreateFromClipSpanish() throws { try createFromClip(language: "es") }

    @MainActor
    private func launch(language: String, library: Bool) throws -> (XCUIApplication, XCUIElement) {
        let app = GanchoUITestApplication()
        let nonce = UUID().uuidString
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item", "-use-temp-durable-store",
            "-seed-clip-editing", "-start-capture-paused", "-place-panel-for-ui-test",
            "-place-library-for-ui-test", "-suppress-storage-notice-for-ui-test",
            "-command-nonce", nonce, "-AppleLanguages", "(\(language))"
        ]
        app.launch()
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertTrue(app.textFields["search-field"].firstMatch.waitForExistence(timeout: 15))
        try SynthesizedInput.requireForeground(app)
        if library { GanchoUITestCommands.post("library", token: nonce) }
        let window =
            library
            ? app.windows[language == "en" ? "Library" : "Biblioteca"].firstMatch
            : app.descendants(matching: .any)["history-panel"].firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        return (app, window)
    }

    @MainActor
    private func prompt(_ app: XCUIApplication) -> XCUIElement {
        let field = app.sheets.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the native name prompt must open")
        return field
    }

    @MainActor
    private func confirmation(
        _ app: XCUIApplication, language: String, rename: Bool = false
    )
        -> XCUIElement
    {
        let title =
            rename
            ? (language == "en" ? "Rename" : "Renombrar") : (language == "en" ? "Create" : "Crear")
        return app.sheets.buttons[title].firstMatch
    }

    @MainActor
    private func rejectEmptyDrafts(
        _ app: XCUIApplication, language: String, rename: Bool = false
    ) throws {
        let field = prompt(app)
        XCTAssertTrue(
            SynthesizedInput.waitForKeyboardFocus(field, timeout: 2),
            "the native name prompt must initially focus its text field")
        try typeTextReliably("", into: field, in: app)
        let confirm = confirmation(app, language: language, rename: rename)
        XCTAssertTrue(confirm.exists)
        try keepRender(of: "@sheet", in: app, named: "\(language) blank board name")
        XCTAssertFalse(
            confirm.isEnabled, "a blank name must disable confirmation before submission")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(field.exists, "Return on an empty draft must preserve the prompt")
        try typeTextReliably("   ", into: field, in: app)
        XCTAssertFalse(confirm.isEnabled, "spaces must not enable confirmation")
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(field.exists, "Return on spaces must preserve the prompt")
        app.typeKey(.tab, modifierFlags: [])
        XCTAssertTrue(field.exists, "Tab navigation must preserve the draft")
        XCTAssertFalse(confirm.isEnabled)
        XCTAssertFalse(
            SynthesizedInput.hasKeyboardFocus(confirm), "Tab must skip disabled confirmation")
    }

    @MainActor
    private func exercise(language: String, library: Bool) throws {
        let (app, window) = try launch(language: language, library: library)
        defer { app.terminate() }
        let newBoard = window.buttons[library ? "library-new-board" : "board-new"].firstMatch
        XCTAssertTrue(newBoard.waitForExistence(timeout: 5))
        let renderTarget = library ? (language == "en" ? "Library" : "Biblioteca") : "history-panel"
        let initialBoards = boardCount(in: window, library: library)
        newBoard.click()
        try rejectEmptyDrafts(app, language: language)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(app.sheets.firstMatch.waitForNonexistence(timeout: 3))

        newBoard.click()
        let name = "Café 日本語"
        try typeTextReliably(" " + name + " ", into: prompt(app), in: app)
        XCTAssertTrue(confirmation(app, language: language).isEnabled)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.sheets.firstMatch.waitForNonexistence(timeout: 5))
        let board = board(named: name, in: window, library: library)
        XCTAssertTrue(board.waitForExistence(timeout: 5), "the Unicode board must be created")
        XCTAssertEqual(
            boardCount(in: window, library: library), initialBoards + 1,
            "invalid submissions must not create boards")
        try keepRender(
            of: renderTarget, in: app,
            named: "\(language) Unicode board created once")

        board.rightClick()
        app.menuItems[language == "en" ? "Rename board…" : "Renombrar tablero…"].firstMatch.click()
        try rejectEmptyDrafts(app, language: language, rename: true)
        try typeTextReliably("Cancelled", into: prompt(app), in: app)
        app.sheets.buttons[language == "en" ? "Cancel" : "Cancelar"].firstMatch.click()
        XCTAssertTrue(board.exists, "cancelling rename must retain the original board")

        board.rightClick()
        app.menuItems[language == "en" ? "Rename board…" : "Renombrar tablero…"].firstMatch.click()
        let renamed = "Café revisado"
        try typeTextReliably(renamed, into: prompt(app), in: app)
        XCTAssertTrue(confirmation(app, language: language, rename: true).isEnabled)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.sheets.firstMatch.waitForNonexistence(timeout: 5))
        XCTAssertTrue(
            self.board(named: renamed, in: window, library: library).waitForExistence(timeout: 5))
        XCTAssertFalse(board.exists)
        XCTAssertEqual(boardCount(in: window, library: library), initialBoards + 1)
        try keepRender(of: renderTarget, in: app, named: "\(language) board renamed once")
    }

    @MainActor
    private func board(named name: String, in window: XCUIElement, library: Bool) -> XCUIElement {
        if library { return window.staticTexts[name].firstMatch }
        return window.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", name)).firstMatch
    }

    @MainActor
    private func boardCount(in window: XCUIElement, library: Bool) -> Int {
        let prefix = library ? "library-board-" : "board-"
        // Favorites is a builtin row loaded asynchronously, not a user board.
        let favorites = prefix + "FA000000-0000-4000-A000-000000000001"
        return window.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH %@ AND identifier MATCHES %@ AND identifier != %@",
                prefix, prefix + "[0-9A-Fa-f-]{36}", favorites)
        ).count
    }

    @MainActor
    private func createFromClip(language: String) throws {
        let (app, panel) = try launch(language: language, library: false)
        defer { app.terminate() }
        let rows = panel.descendants(matching: .any).matching(identifier: "clip-row")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 8))
        let before = rows.count
        let initialBoards = boardCount(in: panel, library: false)
        rows.firstMatch.rightClick()
        let add = app.menuItems[language == "en" ? "Add to board" : "Añadir a un tablero"]
            .firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 3))
        add.hover()
        app.menuItems[language == "en" ? "New board…" : "Nuevo tablero…"].firstMatch.click()
        try rejectEmptyDrafts(app, language: language)
        try typeTextReliably("Clip café", into: prompt(app), in: app)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.sheets.firstMatch.waitForNonexistence(timeout: 5))
        let board = board(named: "Clip café", in: panel, library: false)
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        XCTAssertEqual(boardCount(in: panel, library: false), initialBoards + 1)
        let filedCount = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label ENDSWITH %@", " · 1"), object: board)
        XCTAssertEqual(
            XCTWaiter.wait(for: [filedCount], timeout: 5), .completed,
            "the new board's durable count must confirm the original clip was filed")
        XCTAssertEqual(rows.count, before, "creating from a clip must preserve history")
        board.click()
        let count = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count == 1"), object: rows)
        XCTAssertEqual(XCTWaiter.wait(for: [count], timeout: 5), .completed)
        try keepRender(
            of: "history-panel", in: app, named: "\(language) new board contains the original clip")
    }
}

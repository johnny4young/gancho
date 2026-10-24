import XCTest

/// Dragging a clip onto a board: the panel's rail chips and the Library's
/// sidebar rows file it, the toast names the board, and Undo or ⌘Z takes it back.
final class BoardDropUITests: XCTestCase {
    private static let nonce = "board-drop-ui-test"

    @MainActor
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item", "-use-temp-durable-store",
            "-seed-visual-library", "-seed-sample-boards", "-force-free-tier",
            "-start-capture-paused", "-suppress-paused-notice-for-ui-test",
            "-suppress-storage-notice-for-ui-test", "-place-panel-for-ui-test",
            "-opaque-panel-for-ui-test", "-command-nonce", Self.nonce, "-AppleLanguages", "(en)",
            "-ui-test-defaults-suite", "com.johnny4young.gancho.uitests.drop.\(UUID().uuidString)"
        ]
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 5)
        return app
    }

    @MainActor
    private func rows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "clip-row")
    }

    @MainActor
    private func codeRow(_ app: XCUIApplication) -> XCUIElement {
        rows(app).matching(NSPredicate(format: "label BEGINSWITH %@", "code,")).firstMatch
    }

    @MainActor
    private func railChip(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'board-' AND label BEGINSWITH %@", name)
        ).firstMatch
    }

    /// Slow, with a dwell over the target, so AppKit sees the drag enter it
    /// before the mouse-up even under load.
    @MainActor
    private func drag(_ source: XCUIElement, onto target: XCUIElement) {
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.5)).press(
            forDuration: 1.0,
            thenDragTo: target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
            withVelocity: .default, thenHoldForDuration: 0.8)
    }

    /// Waits for the toast to say `text`; on a miss, says what it showed.
    @MainActor
    private func assertToast(
        _ text: String, in app: XCUIApplication, file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let toast = app.descendants(matching: .any)["gancho-toast"].firstMatch
        var texts: [String] = []
        let deadline = Date().addingTimeInterval(8)
        repeat {
            texts =
                toast.exists
                ? toast.staticTexts.allElementsBoundByIndex.map {
                    $0.label.isEmpty ? $0.value as? String ?? "" : $0.label
                } : []
            if texts.contains(text) { return }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline
        XCTFail("toast should say \(text); it showed \(texts)", file: file, line: line)
    }

    @MainActor
    func testDroppingARowOnARailChipFilesItAndUndoTakesItBack() throws {
        let app = launch()
        defer { app.terminate() }
        let row = codeRow(app)
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        let chip = railChip("Seed board 1", in: app)
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        try SynthesizedInput.requireForeground(app)

        drag(row, onto: chip)
        assertToast("Added to Seed board 1", in: app)
        XCTAssertTrue(app.buttons["toast-undo"].firstMatch.exists)

        drag(row, onto: chip)
        assertToast("Already in Seed board 1", in: app)

        chip.click()
        XCTAssertTrue(codeRow(app).waitForExistence(timeout: 5), "the board now holds the clip")
        XCTAssertEqual(rows(app).count, 1)
    }

    @MainActor
    func testCommandZUndoesTheDrop() throws {
        let app = launch()
        defer { app.terminate() }
        let row = codeRow(app)
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        let chip = railChip("Seed board 2", in: app)
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        try SynthesizedInput.requireForeground(app)

        drag(row, onto: chip)
        assertToast("Added to Seed board 2", in: app)
        app.typeKey("z", modifierFlags: .command)
        XCTAssertTrue(
            app.buttons["toast-undo"].firstMatch.waitForNonExistence(timeout: 5),
            "⌘Z runs the toast's Undo and closes it")

        chip.click()
        let deadline = Date().addingTimeInterval(3)
        while rows(app).firstMatch.exists, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertEqual(rows(app).count, 0, "the clip left the board again")
    }

    /// With no toast on screen, ⌘Z stays the search field's own undo.
    @MainActor
    func testCommandZWithoutAToastUndoesTyping() throws {
        let app = launch()
        defer { app.terminate() }
        let field = app.textFields["search-field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        try typeTextReliably("ocean", into: field, in: app)
        app.typeKey("z", modifierFlags: .command)
        let deadline = Date().addingTimeInterval(3)
        while (field.value as? String ?? "") == "ocean", Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertNotEqual(field.value as? String, "ocean", "the field undid the typing")
    }

    @MainActor
    func testDroppingALibraryCardOnASidebarBoard() throws {
        let app = launch()
        defer { app.terminate() }
        XCTAssertTrue(codeRow(app).waitForExistence(timeout: 15))
        GanchoUITestCommands.post("library", token: Self.nonce)
        let card = app.descendants(matching: .any).matching(identifier: "library-clip")
            .matching(NSPredicate(format: "label BEGINSWITH %@", "Example")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10))
        // Favorites comes first; the seeded board is found by its name.
        let board = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'library-board-'"))
            .containing(
                NSPredicate(format: "label == %@ OR value == %@", "Seed board 1", "Seed board 1")
            )
            .firstMatch
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        try SynthesizedInput.requireForeground(app)

        drag(card, onto: board)
        assertToast("Added to Seed board 1", in: app)
    }

    /// A row drag carries a clip; the panel stays put and moves from its top strip.
    @MainActor
    func testRowDragLeavesThePanelWhereItIs() throws {
        let app = launch()
        defer { app.terminate() }
        let panel = app.descendants(matching: .any).matching(identifier: "history-panel")
            .firstMatch
        let row = codeRow(app)
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        try SynthesizedInput.requireForeground(app)
        let before = panel.frame
        let start = row.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.5))
        start.press(
            forDuration: 1.0, thenDragTo: start.withOffset(CGVector(dx: 120, dy: 140)),
            withVelocity: .default, thenHoldForDuration: 0.3)
        XCTAssertEqual(panel.frame, before, "a row drag must not move the panel")

        let strip = panel.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01))
        strip.press(
            forDuration: 0.3, thenDragTo: strip.withOffset(CGVector(dx: 60, dy: 40)),
            withVelocity: .default, thenHoldForDuration: 0.3)
        XCTAssertNotEqual(panel.frame.origin, before.origin, "the top strip moves the panel")
    }
}

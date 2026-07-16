import AppKit
import XCTest

/// Board flows in the history panel — the ⌘B picker, ⇧⌘B repeat-last, and the
/// board rail filter. Split from `PanelUITests` (the panel smoke was at the
/// type-body budget); same deterministic `-open-panel-on-launch` hooks.
final class PanelBoardUITests: XCTestCase {
    @MainActor
    func testBoardPickerCreatesBoardAndRepeatLastShortcutFilesAnotherClip() throws {
        let app = launchWithPanel()
        defer { app.terminate() }
        XCTAssertTrue(app.textFields["search-field"].firstMatch.waitForExistence(timeout: 8))

        let rows = app.descendants(matching: .any).matching(identifier: "clip-row")
        try XCTSkipUnless(
            rows.firstMatch.waitForExistence(timeout: 8),
            "seeded clip rows not exposed to the UI runner in this environment")
        let settle = Date().addingTimeInterval(3)
        while rows.count < 2 && Date() < settle {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        let allRows = rows.allElementsBoundByIndex
        try XCTSkipUnless(allRows.count >= 2, "not enough seeded rows exposed (\(allRows.count))")

        try SynthesizedInput.requireForeground(app)
        app.typeKey("b", modifierFlags: .command)
        let picker = app.descendants(matching: .any)["board-picker"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "⌘B must open the board picker")
        try typeBoardPickerFilter("Review queue", in: app)
        XCTAssertTrue(
            app.descendants(matching: .any)["board-picker-create-row"].firstMatch
                .waitForExistence(timeout: 3),
            "typing a new board name must offer a create row")

        app.typeKey(.return, modifierFlags: .command)
        let pickerCloseResult = XCTWaiter().wait(
            for: [
                XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "exists == false"), object: picker)
            ],
            timeout: 6)
        XCTAssertEqual(
            pickerCloseResult, .completed,
            "⌘↩ must create, file, remember the board, and close the picker")

        allRows[1].click()
        app.typeKey("b", modifierFlags: [.command, .shift])
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))

        app.typeKey("b", modifierFlags: .command)
        let reopenedPicker = app.descendants(matching: .any)["board-picker"].firstMatch
        XCTAssertTrue(
            reopenedPicker.waitForExistence(timeout: 5), "⌘B must reopen the board picker")
        try typeBoardPickerFilter("Review queue", in: app)
        let createdBoardRow = app.descendants(matching: .any)["board-picker-board-row"].firstMatch
        XCTAssertTrue(createdBoardRow.waitForExistence(timeout: 3))
        let repeatedBoardSelection = XCTWaiter().wait(
            for: [
                XCTNSPredicateExpectation(
                    predicate: NSPredicate(format: "value == %@", "Selected"),
                    object: createdBoardRow)
            ],
            timeout: 3)
        XCTAssertEqual(
            repeatedBoardSelection, .completed,
            "⇧⌘B must repeat the newly created board on the next selected clip")
    }

    @MainActor
    func testBoardChipFiltersToTheFiledClipAndCapturesEvidence() throws {
        let app = launchWithPanel()
        defer { app.terminate() }
        XCTAssertTrue(app.textFields["search-field"].firstMatch.waitForExistence(timeout: 8))

        let rows = app.descendants(matching: .any).matching(identifier: "clip-row")
        try XCTSkipUnless(
            rows.firstMatch.waitForExistence(timeout: 8),
            "seeded clip rows not exposed to the UI runner in this environment")
        let settle = Date().addingTimeInterval(3)
        while rows.count < 2 && Date() < settle {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        try XCTSkipUnless(rows.count >= 2, "not enough seeded rows exposed (\(rows.count))")

        // File the selected clip into a fresh board (⌘B → name → ⌘↩).
        try SynthesizedInput.requireForeground(app)
        app.typeKey("b", modifierFlags: .command)
        let picker = app.descendants(matching: .any)["board-picker"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "⌘B must open the board picker")
        try typeBoardPickerFilter("Paged board", in: app)
        XCTAssertTrue(
            app.descendants(matching: .any)["board-picker-create-row"].firstMatch
                .waitForExistence(timeout: 3))
        app.typeKey(.return, modifierFlags: .command)
        XCTAssertTrue(picker.waitForNonExistence(timeout: 6))

        // Select the new board on the rail — from here the rows come through
        // the paged board query, not the recent browse.
        let chip = app.descendants(matching: .any)
            .matching(
                NSPredicate(
                    format: "identifier BEGINSWITH 'board-' AND label CONTAINS[c] %@",
                    "Paged board")
            )
            .firstMatch
        XCTAssertTrue(
            chip.waitForExistence(timeout: 5), "the created board must appear on the rail")
        chip.click()

        // Exactly the filed clip remains visible under the board filter.
        let narrowed = Date().addingTimeInterval(5)
        while rows.count != 1 && Date() < narrowed {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertEqual(rows.count, 1, "the board view must show exactly the filed clip")

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "macOS board filter (paged query)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func launchWithPanel() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item",
            "-use-temp-durable-store", "-seed-panel-repro", "-force-free-tier"
        ]
        app.launch()
        let deadline = Date().addingTimeInterval(5)
        while app.state == .notRunning && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        _ = app.wait(for: .runningForeground, timeout: 5)
        return app
    }

    @MainActor
    private func typeBoardPickerFilter(
        _ text: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let identifiedField = app.textFields["board-picker-filter"].firstMatch
        if identifiedField.waitForExistence(timeout: 2) {
            try typeTextReliably(text, into: identifiedField, in: app, file: file, line: line)
            return
        }

        let labelledField = app.textFields["Filter or new board name"].firstMatch
        guard labelledField.waitForExistence(timeout: 2) else {
            XCTFail("the picker filter must exist before typing", file: file, line: line)
            return
        }

        try typeTextReliably(text, into: labelledField, in: app, file: file, line: line)
    }
}

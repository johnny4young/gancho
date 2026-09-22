import XCTest

/// Exercises a real same-context refresh through durable title editing, then
/// Enter through the existing no-write/no-key-event paste sink. Only synthetic
/// rows in disposable storage are used; the system clipboard is untouched.
final class PanelSelectionStabilityUITests: XCTestCase {
    @MainActor
    func testSelectedIdentitySurvivesEditRefreshAndEnterPastes() throws {
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item",
            "-use-temp-durable-store", "-seed-source-apps", "-start-capture-paused",
            "-ui-test-paste-sink", "pasted", "-AppleLanguages", "(en)"
        ]
        app.launch()
        defer { app.terminate() }

        let rows = app.descendants(matching: .any).matching(identifier: "clip-row")
        let target = rows.matching(NSPredicate(format: "label CONTAINS %@", "Safari source alpha"))
            .firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 10))
        XCTAssertTrue(target.isHittable)
        XCTAssertFalse(
            rows.firstMatch.label.contains("Safari source alpha"), "exercise a non-first row")
        try SynthesizedInput.requireForeground(app)
        target.click()
        XCTAssertTrue(target.isSelected)

        let edit = app.buttons["preview-edit-title"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.click()
        let field = app.textFields["preview-title-field"].firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 3))
        field.click()
        field.typeKey("a", modifierFlags: .command)
        let title = "Stable synthetic selection"
        field.typeText(title)
        app.buttons["preview-save-title"].firstMatch.click()

        // The row's updated title arrives through search.refresh(), so this is
        // a completion signal, not a sleep that might race the old index reset.
        let renamed = rows.matching(NSPredicate(format: "label CONTAINS %@", title)).firstMatch
        XCTAssertTrue(renamed.waitForExistence(timeout: 5))
        XCTAssertTrue(renamed.isSelected, "the refreshed non-first identity remains selected")
        XCTAssertEqual(rows.allElementsBoundByIndex.filter(\.isSelected).count, 1)

        let search = app.textFields["search-field"].firstMatch
        search.click()
        XCTAssertTrue(SynthesizedInput.waitForKeyboardFocus(search, timeout: 5))
        XCTAssertTrue(renamed.isSelected)
        search.typeKey(.return, modifierFlags: [])
        let panel = app.descendants(matching: .any)["history-panel"].firstMatch
        XCTAssertTrue(
            panel.waitForNonExistence(timeout: 5), "Enter uses the selected-item paste path")
    }
}

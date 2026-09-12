import AppKit
import XCTest

final class SavedFiltersUITests: XCTestCase {
    @MainActor
    func testSaveApplyRenameAndDeleteFilterKeepsClips() throws {
        let app = GanchoUITestApplication()
        let nonce = UUID().uuidString
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item", "-use-temp-durable-store",
            "-seed-clip-editing", "-seed-source-apps", "-force-free-tier", "-start-capture-paused",
            "-ui-test-defaults-suite", "com.johnny4young.gancho.uitests.filters.\(UUID())",
            "-command-nonce", nonce, "-AppleLanguages", "(en)"
        ]
        app.launch()
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        defer { app.terminate() }
        let field = app.textFields["search-field"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        let initialCount = app.descendants(matching: .any).matching(identifier: "clip-row").count
        XCTAssertEqual(initialCount, 4)
        try typeTextReliably("Yesterday", into: field, in: app)
        app.buttons["filter-save"].click()
        let name = app.textFields["filter-name-field"]
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        try typeTextReliably("Daily notes", into: name, in: app)
        app.buttons["filter-confirm"].click()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5))
        try SynthesizedInput.requireForeground(app)
        GanchoUITestCommands.post("library", token: nonce)
        let library = app.windows["Library"]
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        XCTAssertTrue(app.dialogs["history-panel"].waitForNonExistence(timeout: 5))
        let row = library.staticTexts["saved-filter-row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertEqual(row.value as? String, "Daily notes")
        row.click()
        let clips = library.descendants(matching: .any).matching(identifier: "library-clip")
        XCTAssertTrue(clips.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(clips.count, 1)
        row.rightClick()
        app.menuItems["Edit filter…"].click()
        XCTAssertTrue(name.waitForExistence(timeout: 5))
        try typeTextReliably("Renamed notes", into: name, in: app)
        app.buttons["filter-confirm"].click()
        let renamed = library.staticTexts["saved-filter-row"].firstMatch
        let updated = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Renamed notes"), object: renamed)
        XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 5), .completed)
        let attachment = XCTAttachment(screenshot: library.screenshot())
        attachment.name = "Saved filter — synthetic query"
        attachment.lifetime = .keepAlways
        add(attachment)
        renamed.rightClick()
        app.menuItems["Delete filter"].click()
        XCTAssertTrue(renamed.waitForNonExistence(timeout: 5))
        let allClips = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count == %d", initialCount), object: clips)
        XCTAssertEqual(XCTWaiter.wait(for: [allClips], timeout: 5), .completed)
        XCTAssertEqual(
            clips.count, initialCount, "Deleting a filter must preserve all original clips")
    }
}

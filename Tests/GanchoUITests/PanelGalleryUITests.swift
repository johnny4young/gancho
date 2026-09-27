import XCTest

/// ⌘G flips the history between the list and the gallery of cards. Cards keep
/// the row contract (one `clip-row` per clip, one selected), the keyboard still
/// moves the selection, and the choice comes back on relaunch.
final class PanelGalleryUITests: XCTestCase {
    @MainActor
    func testCommandGShowsCardsKeepsSelectionAndIsRemembered() throws {
        let suite = "com.johnny4young.gancho.uitests.panel-gallery-\(UUID().uuidString)"
        let arguments = [
            "-open-panel-on-launch", "-use-in-process-status-item", "-use-temp-durable-store",
            "-seed-visual-library", "-seed-source-apps", "-force-free-tier",
            "-opaque-panel-for-ui-test", "-place-panel-for-ui-test",
            "-suppress-storage-notice-for-ui-test", "-AppleLanguages", "(en)",
            "-ui-test-defaults-suite", suite
        ]
        var app: XCUIApplication = GanchoUITestApplication()
        app.launchArguments = arguments
        app.launch()
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))

        let search = app.textFields["search-field"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        let rows = app.descendants(matching: .any).matching(identifier: "clip-row")
        XCTAssertTrue(rows.element(boundBy: 2).waitForExistence(timeout: 10))
        let listCount = rows.count
        let gallery = app.descendants(matching: .any)["panel-gallery"].firstMatch
        XCTAssertFalse(gallery.exists, "the list is the default layout")

        try SynthesizedInput.requireForeground(app)
        search.click()
        guard SynthesizedInput.waitForKeyboardFocus(search, timeout: 2) else {
            XCTFail("the search field must own keyboard focus before ⌘G")
            return
        }
        app.typeKey("g", modifierFlags: .command)
        XCTAssertTrue(gallery.waitForExistence(timeout: 5), "⌘G must show the gallery")
        XCTAssertEqual(rows.count, listCount, "every clip is one card")
        XCTAssertEqual(rows.allElementsBoundByIndex.filter(\.isSelected).count, 1)

        // → steps to the next card in the row; the selection stays single.
        app.typeKey(.rightArrow, modifierFlags: [])
        let second = rows.element(boundBy: 1)
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isSelected == true"), object: second)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 3), .completed)
        XCTAssertEqual(rows.allElementsBoundByIndex.filter(\.isSelected).count, 1)

        let panel = app.dialogs["history-panel"].firstMatch
        let evidence = XCTAttachment(screenshot: panel.screenshot())
        evidence.name = "History panel — gallery"
        evidence.lifetime = .keepAlways
        add(evidence)

        app.terminate()
        app = GanchoUITestApplication()
        app.launchArguments = arguments + ["-preserve-ui-test-defaults"]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(
            app.descendants(matching: .any)["panel-gallery"].firstMatch.waitForExistence(
                timeout: 15),
            "the gallery layout must come back on relaunch")
    }
}

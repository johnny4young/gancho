import XCTest

/// The share extension end to end: Safari shares a page, the sheet shows what
/// will be saved, and Gancho receives it with the title, board and pin chosen.
final class ShareSheetUITests: XCTestCase {
    @MainActor
    func testSharingFromSafariSavesTheTitleBoardAndPin() throws {
        let gancho = XCUIApplication()
        gancho.launchArguments = [
            "-skip-welcome-on-launch", "-use-temp-durable-store", "-seed-sample-boards",
            "-AppleLanguages", "(en)"
        ]
        gancho.launch()
        defer { gancho.terminate() }
        guard
            gancho.descendants(matching: .any)["capture-screen"].firstMatch
                .waitForExistence(timeout: 10)
        else { throw XCTSkip("capture screen is not reachable on this runner") }
        // The seeded boards must exist before the sheet reads their snapshot.
        let seeded = gancho.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Seed board 1")
        ).firstMatch
        XCTAssertTrue(seeded.waitForExistence(timeout: 10))

        let safari = try openShareSheetInSafari()
        defer { safari.terminate() }
        let save = safari.descendants(matching: .any)["share-save-button"].firstMatch
        XCTAssertTrue(save.waitForExistence(timeout: 10), "the sheet shows what will be saved")
        let preview = safari.descendants(matching: .any)["share-preview"].firstMatch
        XCTAssertTrue(preview.label.contains("example.com"), preview.label)
        // The field starts with the page title the sharing app handed over.
        let title = safari.textFields["share-title-field"].firstMatch
        title.tap()
        let current = (title.value as? String) ?? ""
        title.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
        title.typeText("Synthetic share")
        let board = safari.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == 'share-board-chip' AND label == 'Seed board 1'")
        ).firstMatch
        XCTAssertTrue(board.exists)
        board.tap()
        XCTAssertTrue(board.isSelected)
        let pin = safari.switches["share-pin-toggle"].switches.firstMatch
        pin.tap()
        XCTAssertEqual(pin.value as? String, "1")
        save.tap()
        XCTAssertTrue(
            save.waitForNonExistence(timeout: 5), "the sheet closes once the share is saved")

        gancho.activate()
        let row = gancho.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == 'clip-row' AND label CONTAINS %@", "example.com")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "the shared page arrives")
        row.tap()
        let titled = gancho.descendants(matching: .any).matching(
            NSPredicate(format: "label == %@ OR value == %@", "Synthetic share", "Synthetic share")
        ).firstMatch
        XCTAssertTrue(titled.waitForExistence(timeout: 5), "titled as typed in the sheet")
        XCTAssertTrue(
            gancho.buttons["Pinned"].firstMatch.waitForExistence(timeout: 5), "and pinned")
        gancho.buttons["Done"].firstMatch.tap()
        let chip = gancho.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Seed board 1")
        ).firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 5))
        chip.tap()
        XCTAssertTrue(
            row.waitForExistence(timeout: 5), "and on the board chosen in the sheet")
    }

    /// Safari on a page, its share sheet, and Gancho picked from the row.
    @MainActor
    private func openShareSheetInSafari() throws -> XCUIApplication {
        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        XCUIDevice.shared.system.open(URL(string: "https://example.com")!)
        guard safari.wait(for: .runningForeground, timeout: 15) else {
            throw XCTSkip("Safari did not open on this runner")
        }
        let more = safari.buttons["MoreMenuButton"].firstMatch
        guard more.waitForExistence(timeout: 10) else { throw XCTSkip("no Safari menu") }
        more.tap()
        let share = safari.descendants(matching: .any).matching(
            NSPredicate(format: "label == 'Share'")
        ).firstMatch
        XCTAssertTrue(share.waitForExistence(timeout: 5))
        share.tap()
        let target = safari.descendants(matching: .any).matching(
            NSPredicate(format: "label == 'Gancho' OR label == 'Save to Gancho'")
        ).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 10), "Gancho is offered in the share sheet")
        target.tap()

        return safari
    }
}

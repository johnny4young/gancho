import AppKit
import XCTest

/// These flows run on disposable CI hosts with synthetic clips, isolated
/// defaults and the clipboard isolation enforced by GanchoUITestApplication.
final class AppQualityUITests: XCTestCase {
    @MainActor
    func testSettingsNavigationEnglishLight() throws {
        try verifySettings(language: "en", appearance: "light")
    }

    @MainActor
    func testSettingsNavigationSpanishDark() throws {
        try verifySettings(language: "es", appearance: "dark")
    }

    @MainActor
    private func verifySettings(language: String, appearance: String) throws {
        let app = GanchoUITestApplication()
        let token = UUID().uuidString
        app.launchArguments = [
            "-regular-activation-for-ui-tests", "-use-in-process-status-item",
            "-has-seen-welcome", "YES", "-start-capture-paused",
            "-open-deep-link-on-launch", "gancho://settings",
            "-AppleLanguages", "(\(language))", "-appearance", appearance,
            "-command-nonce", token
        ]
        app.launch()
        defer { app.terminate() }
        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 8))
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        for section in [
            "general", "capture", "retention", "privacy", "integrations", "pro", "about"
        ] {
            let button = window.buttons["settings-tab-\(section)"].firstMatch
            XCTAssertTrue(button.waitForExistence(timeout: 3))
            button.click()
            keep(window, name: "settings-\(section)-\(language)-\(appearance)")
            XCTAssertTrue(button.isSelected, "the current Settings section must expose selection")
        }
        let close = try XCTUnwrap(
            window.buttons.matching(NSPredicate(format: "subrole == 'AXCloseButton'"))
                .allElementsBoundByIndex.first)
        close.click()
        XCTAssertTrue(window.waitForNonExistence(timeout: 5))
        GanchoUITestCommands.post("settings", token: token)
        XCTAssertTrue(window.waitForExistence(timeout: 5))
        XCTAssertTrue(window.buttons["settings-tab-about"].firstMatch.isSelected)
    }

    @MainActor
    func testBoardPickerExposesButtonsAndEscapeReturnsToSearch() throws {
        let (app, _) = try launchPanel()
        defer { app.terminate() }
        app.typeKey("b", modifierFlags: .command)
        let picker = app.descendants(matching: .any)["board-picker"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        keep(app.dialogs["history-panel"].firstMatch, name: "panel-board-picker")
        let board = picker.buttons["board-picker-board-row"].firstMatch
        XCTAssertTrue(
            board.waitForExistence(timeout: 3),
            "a board must support native accessibility activation")
        let filter = picker.textFields["board-picker-filter"].firstMatch
        XCTAssertTrue(filter.waitForExistence(timeout: 3))
        filter.click()
        filter.typeText("Synthetic review board")
        let create = picker.buttons["board-picker-create-row"].firstMatch
        XCTAssertTrue(create.waitForExistence(timeout: 3))
        create.click()
        XCTAssertTrue(picker.waitForNonExistence(timeout: 6))
        app.typeKey("b", modifierFlags: .command)
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(picker.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.dialogs["history-panel"].firstMatch.exists)
        let search = app.textFields["search-field"].firstMatch
        search.click()
        search.typeText("Ocean")
        XCTAssertTrue(app.buttons["search-clear"].firstMatch.waitForExistence(timeout: 3))
        app.buttons["search-clear"].firstMatch.click()
        XCTAssertEqual(search.value as? String, "")
    }

    @MainActor
    func testLibraryReceivesPanelCurationWithoutReopening() throws {
        let (app, token) = try launchPanel()
        defer { app.terminate() }
        GanchoUITestCommands.post("library", token: token)
        let library = app.windows["Library"].firstMatch
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        let empty = library.staticTexts["No snippets yet"].firstMatch
        XCTAssertTrue(empty.waitForExistence(timeout: 5))
        keep(library, name: "library-before-panel-curation")
        GanchoUITestCommands.post("openPanel", token: token)
        let row = app.descendants(matching: .any).matching(identifier: "clip-row")
            .matching(NSPredicate(format: "label CONTAINS %@", "let greeting")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()
        app.typeKey("s", modifierFlags: .command)
        XCTAssertTrue(
            empty.waitForNonExistence(timeout: 8),
            "a confirmed panel mutation must refresh the open Library")
        GanchoUITestCommands.post("library", token: token)
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        keep(library, name: "library-after-panel-curation")
    }

    @MainActor
    private func launchPanel() throws -> (XCUIApplication, String) {
        let app = GanchoUITestApplication()
        let token = UUID().uuidString
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item", "-use-temp-durable-store",
            "-seed-visual-library", "-start-capture-paused", "-has-seen-welcome", "YES",
            "-opaque-panel-for-ui-test", "-place-panel-for-ui-test", "-place-library-for-ui-test",
            "-suppress-storage-notice-for-ui-test", "-command-nonce", token
        ]
        app.launch()
        app.activate()
        guard app.wait(for: .runningForeground, timeout: 5) else {
            XCTFail("the isolated app must be frontmost before sending input")
            app.terminate()
            throw CocoaError(.coderInvalidValue)
        }
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "clip-row")
                .element(boundBy: 3).waitForExistence(timeout: 15))
        return (app, token)
    }

    @MainActor
    private func keep(_ window: XCUIElement, name: String) {
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

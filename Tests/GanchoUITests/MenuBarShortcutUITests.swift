import AppKit
import XCTest

final class MenuBarShortcutUITests: XCTestCase {
    /// The Open panel item must show the shortcut the user recorded, not a
    /// fixed ⇧⌘V.
    @MainActor
    func testStatusMenuShowsTheRecordedPanelShortcut() throws {
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item",
            "-diagnose-menu-shortcut-for-ui-test",
            // ⌥⌘V in KeyboardShortcuts' stored form, as a plist string so the
            // argument domain keeps it.
            "-KeyboardShortcuts_toggle-panel",
            #""{\"carbonKeyCode\":9,\"carbonModifiers\":2304}""#
        ]
        app.launch()
        defer { app.terminate() }
        _ = app.wait(for: .runningForeground, timeout: 5)

        let statusItem = app.statusItems.firstMatch
        guard statusItem.waitForExistence(timeout: 5), statusItem.isHittable else {
            throw XCTSkip("status item not hittable on this display/Space")
        }
        statusItem.click()
        let openPanel = app.menuItems["menu-bar-command-openPanel"].firstMatch
        XCTAssertTrue(openPanel.waitForExistence(timeout: 3))
        let optionCommand = NSEvent.ModifierFlags([.command, .option]).rawValue
        XCTAssertEqual(openPanel.value as? String, "menu-shortcut:v:\(optionCommand)")
    }

    /// While the menu tracks, the global panel hotkey is paused, so a press is
    /// handled once by the menu item instead of again when the menu closes.
    @MainActor
    func testGlobalPanelShortcutPausesWhileTheMenuIsOpen() throws {
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item",
            "-diagnose-global-shortcut-for-ui-test"
        ]
        app.launch()
        defer { app.terminate() }
        _ = app.wait(for: .runningForeground, timeout: 5)

        let statusItem = app.statusItems.firstMatch
        guard statusItem.waitForExistence(timeout: 5), statusItem.isHittable else {
            throw XCTSkip("status item not hittable on this display/Space")
        }
        XCTAssertTrue(registration(of: statusItem).hasPrefix("global-shortcut-enabled"))
        statusItem.click()
        let openPanel = app.menuItems["menu-bar-command-openPanel"].firstMatch
        XCTAssertTrue(openPanel.waitForExistence(timeout: 3))
        XCTAssertTrue(registration(of: statusItem).hasPrefix("global-shortcut-disabled"))
        // Choosing an item closes the menu; the hotkey must come back.
        openPanel.click()
        let restored = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value BEGINSWITH %@", "global-shortcut-enabled"),
            object: statusItem)
        XCTAssertEqual(
            XCTWaiter().wait(for: [restored], timeout: 4), .completed,
            "panel hotkey stays paused after the menu closed: \(registration(of: statusItem))")
    }

    private func registration(of statusItem: XCUIElement) -> String {
        statusItem.value as? String ?? ""
    }
}

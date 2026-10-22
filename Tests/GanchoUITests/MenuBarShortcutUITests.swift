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
}

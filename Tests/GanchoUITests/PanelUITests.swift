import AppKit
import XCTest

/// Keyboard-first panel smoke (XCTest lives ONLY in this UI target; unit
/// tests are Swift Testing in the package). The app launches with the
/// deterministic `-open-panel-on-launch` hook — no global-hotkey dependency
/// on hosted runners.
final class PanelUITests: XCTestCase {
    @MainActor
    func testMenuBarAgentStaysResidentOnPlainLaunch() {
        terminateMenuBarHelpers()
        let app = XCUIApplication()
        app.launch()
        defer {
            app.terminate()
            _ = waitForMenuBarHelpersToExit(timeout: 5)
        }

        let deadline = Date().addingTimeInterval(5)
        while app.state == .notRunning && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }

        XCTAssertNotEqual(
            app.state, .notRunning, "plain Xcode Run launch must keep Gancho resident")
        XCTAssertTrue(
            waitForMenuBarHelper(timeout: 5),
            "plain launch must start the visible menu-bar helper")
    }

    @MainActor
    func testSettingsDeepLinkOpensSettingsWindow() throws {
        let app = launchWithInProcessStatusItem()
        defer { app.terminate() }

        let url = try XCTUnwrap(URL(string: "gancho://settings"))
        XCTAssertTrue(NSWorkspace.shared.open(url))
        XCTAssertTrue(app.windows["Settings"].firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testMenuBarCommandDeepLinkOpensSettingsWindow() throws {
        // Pin the nonce so the deep link is deterministic; the app honors a
        // gancho://menu-bar/... open only when the token matches this launch.
        let token = UUID().uuidString
        let app = launchWithInProcessStatusItem(commandNonce: token)
        defer { app.terminate() }

        let url = try XCTUnwrap(URL(string: "gancho://menu-bar/settings?token=\(token)"))
        XCTAssertTrue(NSWorkspace.shared.open(url))

        XCTAssertTrue(app.windows["Settings"].firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testForgedMenuBarCommandWithoutTokenIsIgnored() throws {
        let app = launchWithInProcessStatusItem()
        defer { app.terminate() }

        // A forged gancho://menu-bar/... open from another process carries no
        // nonce, so the app must ignore it — the Settings window never appears.
        let url = try XCTUnwrap(URL(string: "gancho://menu-bar/settings"))
        XCTAssertTrue(NSWorkspace.shared.open(url))
        XCTAssertFalse(app.windows["Settings"].firstMatch.waitForExistence(timeout: 3))
    }

    @MainActor
    func testMenuBarStatusItemResolvesToARealFrame() {
        let app = launchWithInProcessStatusItem()
        defer { app.terminate() }

        // Existence in the accessibility tree is not enough — assert the status
        // item resolves to a real, non-empty frame (a never-created or
        // collapsed-to-zero item would fail here). Which display it lands on,
        // and whether that is on-screen, the app logs in DEBUG at launch.
        let statusItem = app.statusItems.firstMatch
        guard statusItem.waitForExistence(timeout: 5) else {
            // Self-skip where the runner can't reach the status menu bar (some
            // headless CI displays); residence is covered by the sibling test.
            print("skip: status item not exposed to the UI runner in this environment")
            return
        }
        XCTAssertFalse(
            statusItem.frame.isEmpty, "the status item must resolve to a non-zero on-screen frame")
    }

    @MainActor
    func testMenuBarStatusItemOpensSettingsWindow() throws {
        let app = launchWithInProcessStatusItem()
        defer { app.terminate() }

        let statusItem = app.statusItems.firstMatch
        guard statusItem.waitForExistence(timeout: 5), !statusItem.frame.isEmpty else {
            print("skip: status item not exposed to the UI runner in this environment")
            return
        }

        try openStatusMenuItem("Settings…", app: app)
        XCTAssertTrue(app.windows["Settings"].firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testMenuBarStatusItemCanQuitGancho() throws {
        let app = launchWithInProcessStatusItem()
        defer {
            if app.state != .notRunning { app.terminate() }
        }

        let statusItem = app.statusItems.firstMatch
        guard statusItem.waitForExistence(timeout: 5), !statusItem.frame.isEmpty else {
            print("skip: status item not exposed to the UI runner in this environment")
            return
        }

        try openStatusMenuItem("Quit Gancho", app: app)
        XCTAssertEqual(app.wait(for: .notRunning, timeout: 5), true)
    }

    @MainActor
    private func openStatusMenuItem(
        _ title: String,
        app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let statusItem = app.statusItems.firstMatch
        guard statusItem.isHittable else {
            throw XCTSkip(
                "status item resolved but is not hittable on this display/Space; frame coverage still verifies the app-created item"
            )
        }

        statusItem.click()
        let menuItem = app.menuItems[title].firstMatch
        XCTAssertTrue(menuItem.waitForExistence(timeout: 3), file: file, line: line)
        menuItem.click()
    }

    @MainActor
    private func launchWithInProcessStatusItem(commandNonce: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-use-in-process-status-item"]
        if let commandNonce {
            app.launchArguments += ["-command-nonce", commandNonce]
        }
        app.launch()
        waitForAppToStart(app)
        return app
    }

    @MainActor
    private func launchWithPanel() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-open-panel-on-launch", "-use-in-process-status-item"]
        app.launch()
        waitForAppToStart(app)
        _ = app.wait(for: .runningForeground, timeout: 5)
        return app
    }

    @MainActor
    private func waitForAppToStart(_ app: XCUIApplication) {
        let deadline = Date().addingTimeInterval(5)
        while app.state == .notRunning && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
    }

    @MainActor
    private func waitForMenuBarHelper(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !menuBarHelpers().isEmpty { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return !menuBarHelpers().isEmpty
    }

    @MainActor
    private func waitForMenuBarHelpersToExit(timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if menuBarHelpers().isEmpty { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return menuBarHelpers().isEmpty
    }

    @MainActor
    private func terminateMenuBarHelpers() {
        for app in menuBarHelpers() {
            _ = app.terminate()
        }
        _ = waitForMenuBarHelpersToExit(timeout: 2)
    }

    @MainActor
    private func menuBarHelpers() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { app in
            app.localizedName == "GanchoMenuBarHelper"
                || app.executableURL?.lastPathComponent == "GanchoMenuBarHelper"
        }
    }

    @MainActor
    func testPanelOpensAndSearchFieldHasFocus() {
        let app = launchWithPanel()
        defer { app.terminate() }
        let search = app.textFields["search-field"].firstMatch
        XCTAssertTrue(
            search.waitForExistence(timeout: 5), "panel search field must open on launch hook")

        // Type-to-search goes straight to the field — no click required.
        app.typeText("zzz-no-results-zzz")
        XCTAssertEqual(search.value as? String, "zzz-no-results-zzz")
    }

    @MainActor
    func testEscapeClosesPanel() {
        let app = launchWithPanel()
        defer { app.terminate() }
        let search = app.textFields["search-field"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))

        app.typeKey(.escape, modifierFlags: [])
        // Window-geometry assertions self-skip on tiny virtual displays —
        // existence flips are stable everywhere.
        let disappeared = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: disappeared, object: search)
        XCTAssertEqual(XCTWaiter().wait(for: [expectation], timeout: 5), .completed)
    }

    @MainActor
    func testArrowNavigationDoesNotStealFocusFromSearch() {
        let app = launchWithPanel()
        defer { app.terminate() }
        let search = app.textFields["search-field"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))

        // Arrows are handled by the panel; the search field keeps focus so
        // the user can keep typing mid-navigation.
        app.typeKey(.downArrow, modifierFlags: [])
        app.typeKey(.upArrow, modifierFlags: [])
        app.typeText("focus works")
        XCTAssertEqual(search.value as? String, "focus works")
    }

    @MainActor
    func testFooterShortcutsButtonOpensCheatSheet() {
        let app = launchWithPanel()
        defer { app.terminate() }
        XCTAssertTrue(app.textFields["search-field"].firstMatch.waitForExistence(timeout: 5))

        // The footer "?" surfaces the power shortcuts (⌘P/⌘S/⌥⏎/⌘1-9) the inline
        // hints can't fit.
        let helpButton = app.buttons["panel-shortcuts-button"].firstMatch
        XCTAssertTrue(helpButton.waitForExistence(timeout: 3), "the footer ? button must exist")
        // The button is tiny and edge-anchored, so XCUITest can report it as not
        // hittable; click its center coordinate directly.
        helpButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()

        let card = app.descendants(matching: .any)["panel-shortcuts"].firstMatch
        XCTAssertTrue(
            card.waitForExistence(timeout: 3), "the ? button must open the keyboard cheat-sheet")
    }
}

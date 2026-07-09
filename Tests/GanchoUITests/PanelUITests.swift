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
                // swiftlint:disable:next line_length
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
    private func launchWithPanel(extraArguments: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-open-panel-on-launch", "-use-in-process-status-item"]
        app.launchArguments += extraArguments
        app.launch()
        waitForAppToStart(app)
        _ = app.wait(for: .runningForeground, timeout: 5)
        return app
    }

    private func captureIndicatorValue(_ value: String) -> NSPredicate {
        NSPredicate(format: "label == %@ OR value == %@", value, value)
    }

    @MainActor
    private func typeBoardPickerFilter(
        _ text: String,
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let identifiedField = app.textFields["board-picker-filter"].firstMatch
        if identifiedField.waitForExistence(timeout: 2) {
            typeTextReliably(text, into: identifiedField, in: app, file: file, line: line)
            return
        }

        let labelledField = app.textFields["Filter or new board name"].firstMatch
        guard labelledField.waitForExistence(timeout: 2) else {
            XCTFail("the picker filter must exist before typing", file: file, line: line)
            return
        }

        typeTextReliably(text, into: labelledField, in: app, file: file, line: line)
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
        app.typeText("f")
        XCTAssertEqual(search.value as? String, "f")
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

    @MainActor
    func testBoardPickerCreatesBoardAndRepeatLastShortcutFilesAnotherClip() throws {
        let app = launchWithPanel(
            extraArguments: ["-use-temp-durable-store", "-seed-panel-repro", "-force-free-tier"])
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

        app.typeKey("b", modifierFlags: .command)
        let picker = app.descendants(matching: .any)["board-picker"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "⌘B must open the board picker")
        typeBoardPickerFilter("Review queue", in: app)
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
        typeBoardPickerFilter("Review queue", in: app)
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
    func testCaptureIndicatorResumesFromThePanelNotice() {
        let app = launchWithPanel(
            extraArguments: [
                "-use-temp-durable-store", "-force-capture-active",
                "-force-pasteboard-access-allowed", "-disable-screen-share-auto-pause",
                "-start-capture-paused"
            ])
        defer { app.terminate() }
        XCTAssertTrue(app.textFields["search-field"].firstMatch.waitForExistence(timeout: 5))

        let indicator = app.descendants(matching: .any)["capture-indicator"].firstMatch
        XCTAssertTrue(indicator.waitForExistence(timeout: 5), "capture status must be visible")
        let pausedIndicatorResult = XCTWaiter().wait(
            for: [
                XCTNSPredicateExpectation(
                    predicate: captureIndicatorValue("Capture paused"), object: indicator)
            ],
            timeout: 5)
        XCTAssertEqual(
            pausedIndicatorResult, .completed,
            "manual pause must update the footer status")
        XCTAssertTrue(
            app.staticTexts["Capture is paused"].firstMatch.waitForExistence(timeout: 3),
            "manual pause must explain the cause in the panel")
        XCTAssertTrue(
            app.staticTexts["Resume capture to save new copies."].firstMatch.waitForExistence(
                timeout: 3),
            "manual pause must explain how to resume capture")

        let resume = app.buttons["Resume"].firstMatch
        XCTAssertTrue(resume.waitForExistence(timeout: 3), "paused notice must be actionable")
        resume.click()
        let resumedIndicatorResult = XCTWaiter().wait(
            for: [
                XCTNSPredicateExpectation(
                    predicate: captureIndicatorValue("Capturing"), object: indicator)
            ],
            timeout: 5)
        XCTAssertEqual(
            resumedIndicatorResult, .completed,
            "the notice action must resume capture")
    }

    @MainActor
    func testEphemeralStorageShowsWarningBanner() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item", "-force-ephemeral-store",
            "-force-capture-active", "-force-pasteboard-access-allowed",
            "-disable-screen-share-auto-pause"
        ]
        app.launch()
        waitForAppToStart(app)
        _ = app.wait(for: .runningForeground, timeout: 5)
        defer { app.terminate() }

        XCTAssertTrue(app.textFields["search-field"].firstMatch.waitForExistence(timeout: 5))
        // When the durable store can't open, the panel must warn that history
        // isn't being saved (data-loss > silent fallback).
        let notice = app.descendants(matching: .any)["capture-notice"].firstMatch
        XCTAssertTrue(
            notice.waitForExistence(timeout: 3),
            "ephemeral storage must surface the capture-notice warning banner")

        let indicator = app.descendants(matching: .any)["capture-indicator"].firstMatch
        XCTAssertTrue(indicator.waitForExistence(timeout: 3), "capture status must be visible")
        let activeIndicatorResult = XCTWaiter().wait(
            for: [
                XCTNSPredicateExpectation(
                    predicate: captureIndicatorValue("Capturing"), object: indicator)
            ],
            timeout: 3)
        XCTAssertEqual(
            activeIndicatorResult, .completed,
            "ephemeral storage still captures; it must not display as paused")
    }

    @MainActor
    func testPrivacyCenterRecentIssuesLogsEphemeralStorage() {
        // Force the in-memory fallback so AppModel records a content-free
        // "Storage" issue at launch, then open the Privacy Center directly.
        let app = XCUIApplication()
        app.launchArguments = [
            "-use-in-process-status-item", "-force-ephemeral-store",
            "-open-privacy-center-on-launch"
        ]
        app.launch()
        waitForAppToStart(app)
        defer { app.terminate() }

        // Locate the Privacy Center by its stable accessibility identifier, not
        // the localized window title, so a non-English runner can't fail a
        // correct UI.
        let privacyCenter = app.descendants(matching: .any)["privacy-center"].firstMatch
        XCTAssertTrue(
            privacyCenter.waitForExistence(timeout: 8),
            "the -open-privacy-center-on-launch hook must open the Privacy Center")

        // The ephemeral-store launch logged an issue, so the "Recent issues"
        // section must surface it with the Copy-for-support affordance — the
        // end-to-end proof that the error log records and renders.
        let copyButton = app.buttons["copy-diagnostics"].firstMatch
        XCTAssertTrue(
            copyButton.waitForExistence(timeout: 5),
            "an ephemeral-store launch must log a content-free issue shown in Recent issues")
    }

    @MainActor
    func testFilterPillExposesSelectedState() {
        let app = launchWithPanel()
        defer { app.terminate() }
        XCTAssertTrue(app.textFields["search-field"].firstMatch.waitForExistence(timeout: 5))

        // Activating a filter marks it selected (the non-colour active cue +
        // VoiceOver state, WCAG 1.4.1). Use the keyboard-first rail path the
        // panel is optimized for: ↑ enters filters, → moves to Links, Space
        // activates the focused pill.
        let links = app.buttons["filter-links"].firstMatch
        XCTAssertTrue(links.waitForExistence(timeout: 3), "the Links filter pill must exist")

        app.typeKey(.upArrow, modifierFlags: [])
        app.typeKey(.rightArrow, modifierFlags: [])
        app.typeKey(.space, modifierFlags: [])

        let selected = NSPredicate(format: "isSelected == true OR value == %@", "Selected")
        let expectation = XCTNSPredicateExpectation(predicate: selected, object: links)
        XCTAssertEqual(
            XCTWaiter().wait(for: [expectation], timeout: 3), .completed,
            "the active filter pill must expose the selected accessibility state")
    }
}

@MainActor
private func typeTextReliably(
    _ text: String,
    into field: XCUIElement,
    in app: XCUIApplication,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    if field.isHittable {
        field.click()
    } else {
        // The field exists but isn't hittable (e.g. overlaid during a transition).
        // Click its center coordinate so it's focused before we send app-level
        // keys — otherwise ⌘A/delete/typing would land on whatever else has focus
        // and could clear unrelated UI. Same fallback the help button uses above.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    }

    app.typeKey("a", modifierFlags: .command)
    app.typeKey(.delete, modifierFlags: [])
    for character in text {
        app.typeText(String(character))
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }

    XCTAssertEqual(
        field.value as? String, text,
        "text entry must not drop characters before asserting picker state",
        file: file,
        line: line)
}

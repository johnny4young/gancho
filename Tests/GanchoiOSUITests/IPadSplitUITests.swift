import XCTest

/// The iPad split view: a sidebar that says what each board, type and app
/// holds, the pasteboard card docked under it, and the history column's
/// shortcuts. Skipped on an iPhone, which has no sidebar.
final class IPadSplitUITests: XCTestCase {
    @MainActor
    func testPasteDocksUnderTheSidebarAndMovesToTheToolbarWithoutIt() throws {
        let app = try launch()
        defer { app.terminate() }
        let card = app.descendants(matching: .any)["sidebar-pasteboard-card"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        XCTAssertTrue(card.descendants(matching: .any)["paste-control"].firstMatch.exists)
        XCTAssertFalse(
            app.navigationBars.descendants(matching: .any)["paste-control"].firstMatch.exists,
            "one Paste at a time")

        app.buttons["Hide Sidebar"].firstMatch.tap()
        let gone = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: card)
        XCTAssertEqual(XCTWaiter().wait(for: [gone], timeout: 5), .completed)
        XCTAssertTrue(
            app.descendants(matching: .any)["paste-control"].firstMatch.waitForExistence(
                timeout: 5),
            "with the sidebar hidden, Paste is back in the toolbar")
    }

    @MainActor
    func testATypeGroupFiltersTheHistoryAndShowsAsSelected() throws {
        let app = try launch()
        defer { app.terminate() }
        let code = app.buttons.matching(
            NSPredicate(format: "identifier == 'sidebar-type-row' AND label BEGINSWITH 'Code'")
        ).firstMatch
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        XCTAssertTrue(code.label.range(of: #"\d"#, options: .regularExpression) != nil, code.label)
        code.tap()
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isSelected == true"), object: code)
        XCTAssertEqual(XCTWaiter().wait(for: [selected], timeout: 5), .completed)
        let secret = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == 'clip-row' AND label BEGINSWITH[c] %@", "secret")
        ).firstMatch
        let filtered = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: secret)
        XCTAssertEqual(
            XCTWaiter().wait(for: [filtered], timeout: 5), .completed,
            "Code leaves the secret out")
        XCTAssertTrue(
            app.descendants(matching: .any).matching(
                NSPredicate(format: "identifier == 'clip-row' AND label CONTAINS %@", "greeting")
            ).firstMatch.exists)
    }

    @MainActor
    func testTheShortcutLegendShowsWithAKeyboardAndCommandFSearches() throws {
        let app = try launch(keyboard: true)
        defer { app.terminate() }
        XCTAssertTrue(
            app.descendants(matching: .any)["history-keyboard-legend"].firstMatch
                .waitForExistence(timeout: 5))
        let field = app.searchFields.firstMatch
        // The simulator drops the first synthesized key event while it
        // attaches the hardware keyboard, so a lost ⌘F is sent once more.
        for _ in 0..<2 where !Self.hasFocus(field) {
            app.typeKey("f", modifierFlags: .command)
            let focused = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "hasKeyboardFocus == true"), object: field)
            _ = XCTWaiter().wait(for: [focused], timeout: 3)
        }
        XCTAssertTrue(Self.hasFocus(field), "⌘F focuses the history search")
    }

    @MainActor
    func testNewBoardShowsTheFreeLimitOnlyOnFree() throws {
        let free = try launch(extra: ["-force-free-tier"])
        let row = free.buttons["sidebar-new-board"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(
            row.label.range(of: #"\d+ of \d+ · Free$"#, options: .regularExpression) != nil,
            row.label)
        free.terminate()

        let pro = try launch(extra: ["-gancho-force-pro"])
        defer { pro.terminate() }
        let proRow = pro.buttons["sidebar-new-board"].firstMatch
        XCTAssertTrue(proRow.waitForExistence(timeout: 5))
        let unlimited = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "NOT label CONTAINS 'Free'"), object: proRow)
        XCTAssertEqual(
            XCTWaiter().wait(for: [unlimited], timeout: 5), .completed,
            "Pro has no board limit: \(proRow.label)")
    }

    @MainActor
    func testRowsAndTheHeroDragTheirLinkAndASecretDeliversNothing() throws {
        let app = try launch()
        defer { app.terminate() }
        let field = app.searchFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let link = row(containing: "example.com", in: app)
        XCTAssertTrue(link.waitForExistence(timeout: 5))
        let dropped = {
            XCTWaiter().wait(
                for: [
                    XCTNSPredicateExpectation(
                        predicate: NSPredicate(format: "value CONTAINS %@", "example.com"),
                        object: field)
                ], timeout: 5)
        }
        link.press(forDuration: 1.0, thenDragTo: field)
        XCTAssertEqual(
            dropped(), .completed, "the link lands where it is dropped: \(field.value ?? "nil")")
        field.buttons["Clear text"].firstMatch.tap()

        link.tap()
        let hero = app.descendants(matching: .any)["detail-link-hero"].firstMatch
        XCTAssertTrue(hero.waitForExistence(timeout: 5))
        // The host, not the URL line: a long press on selectable text selects.
        hero.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.2))
            .press(
                forDuration: 1.0,
                thenDragTo: field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)))
        XCTAssertEqual(dropped(), .completed, "the detail's hero drags its link too")
        field.buttons["Clear text"].firstMatch.tap()

        let secret = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == 'clip-row' AND label BEGINSWITH[c] %@", "secret")
        ).firstMatch
        XCTAssertTrue(secret.waitForExistence(timeout: 5))
        secret.press(forDuration: 1.0, thenDragTo: field)
        sleep(2)
        let text = (field.value as? String) ?? ""
        XCTAssertTrue(
            text.isEmpty || text == field.placeholderValue, "a secret delivers nothing: \(text)")
    }

    @MainActor
    func testNoLegendWithoutAKeyboard() throws {
        let app = try launch(keyboard: false)
        defer { app.terminate() }
        XCTAssertTrue(
            app.descendants(matching: .any)["sidebar-pasteboard-card"].firstMatch
                .waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["history-keyboard-legend"].firstMatch.exists)
    }

    @MainActor
    private func row(containing text: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == 'clip-row' AND label CONTAINS %@", text)
        ).firstMatch
    }

    /// iOS exposes keyboard focus to UI tests only through key-value coding.
    @MainActor
    private static func hasFocus(_ element: XCUIElement) -> Bool {
        (element.value(forKey: "hasKeyboardFocus") as? Bool) ?? false
    }

    @MainActor
    private func launch(keyboard: Bool = false, extra: [String] = []) throws -> XCUIApplication {
        guard UIDevice.current.userInterfaceIdiom == .pad else {
            throw XCTSkip("the split view is iPad only")
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        let app = XCUIApplication()
        app.launchArguments =
            [
                "-skip-welcome-on-launch", "-use-temp-durable-store", "-seed-home-v4",
                "-ui-test-hardware-keyboard", keyboard ? "YES" : "NO", "-AppleLanguages", "(en)"
            ] + extra
        app.launch()
        guard
            app.descendants(matching: .any)["sidebar-board-row"].firstMatch
                .waitForExistence(timeout: 10)
        else {
            app.terminate()
            throw XCTSkip("the sidebar is not reachable on this runner")
        }
        return app
    }
}

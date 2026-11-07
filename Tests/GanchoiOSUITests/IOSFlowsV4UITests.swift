import XCTest

/// The v4 iPhone sheets: the detail with Copy first and a link as its hero,
/// boards with the Free limit and snippets, Settings with status subtitles
/// and the capture paths, and the Privacy Center's Verify. Every launch
/// argument here is a DEBUG-only hook on a throwaway store.
final class IOSFlowsV4UITests: XCTestCase {
    @MainActor
    func testDetailPutsCopyFirstAndShowsTheLinkAsItsHero() throws {
        let app = try launch(["-seed-home-v4"])
        defer { app.terminate() }
        let link = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == 'clip-row' AND label CONTAINS %@", "example.com")
        ).firstMatch
        XCTAssertTrue(link.appears(within: 10))
        link.tap()
        expandSheet(in: app)
        for id in ["detail-provenance", "detail-link-hero", "detail-copy"] {
            XCTAssertTrue(
                app.descendants(matching: .any)[id].firstMatch.appears(within: 5), id)
        }
        for id in ["detail-board", "detail-save-snippet"] {
            XCTAssertTrue(app.buttons[id].firstMatch.exists, id)
        }
        let markdown = app.buttons["detail-markdown-link"].firstMatch
        for _ in 0..<3 where !markdown.isHittable { app.swipeUp() }
        XCTAssertTrue(markdown.exists, "a link offers a Markdown link")
        markdown.tap()
        let result = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", "[Synthetic link](")
        )
        .firstMatch
        for _ in 0..<3 where !result.exists { app.swipeUp() }
        XCTAssertTrue(
            result.appears(within: 5), "the Markdown link is titled by the clip")

        // The hero keeps a link editable.
        let edit = app.buttons["detail-edit-link"].firstMatch
        for _ in 0..<3 where !edit.isHittable { app.swipeDown() }
        XCTAssertTrue(edit.appears(within: 5))
        edit.tap()
        XCTAssertTrue(
            app.textViews["detail-content-field"].firstMatch.appears(within: 5),
            "editing a link opens its text")
    }

    @MainActor
    func testSnippetIsOffForASecretAndSetForASnippet() throws {
        let app = try launch(["-seed-home-v4"])
        defer { app.terminate() }
        let secret = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == 'clip-row' AND label BEGINSWITH[c] %@", "secret")
        ).firstMatch
        XCTAssertTrue(secret.appears(within: 10))
        secret.tap()
        let snippet = app.buttons["detail-save-snippet"].firstMatch
        XCTAssertTrue(snippet.appears(within: 5))
        XCTAssertFalse(snippet.isEnabled, "a secret can't become a snippet")
        app.buttons["Done"].firstMatch.tap()

        let notes = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier == 'clip-row' AND label CONTAINS %@", "Ship the onboarding")
        ).firstMatch
        XCTAssertTrue(notes.appears(within: 5))
        notes.tap()
        XCTAssertTrue(snippet.appears(within: 5))
        let saved = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "Saved"), object: snippet)
        XCTAssertEqual(XCTWaiter().wait(for: [saved], timeout: 5), .completed, "shown as set")
        XCTAssertFalse(snippet.isEnabled)
    }

    @MainActor
    func testBoardsShowTheFreeLimitSyncStateAndSnippets() throws {
        let app = try launch(["-seed-sample-boards", "-seed-home-v4", "-force-free-tier"])
        defer { app.terminate() }
        app.buttons["boards-home-open"].firstMatch.tap()
        let limit = app.staticTexts["boards-home-limit"].firstMatch
        XCTAssertTrue(limit.appears(within: 5))
        XCTAssertTrue(
            limit.label.range(of: #"^\d+ of \d+ · Free$"#, options: .regularExpression) != nil,
            limit.label)
        XCTAssertTrue(
            app.staticTexts["On this iPhone"].firstMatch.appears(within: 5),
            "boards say where they live when sync is off")
        let snippet = app.buttons["boards-home-snippet"].firstMatch
        for _ in 0..<3 where !snippet.exists { app.swipeUp() }
        XCTAssertTrue(snippet.appears(within: 5))
        XCTAssertTrue(snippet.label.contains(";standup"), snippet.label)
    }

    @MainActor
    func testNewBoardNeedsANameBeforeCreate() throws {
        let app = try launch([])
        defer { app.terminate() }
        app.buttons["boards-home-open"].firstMatch.tap()
        let newBoard = app.buttons["boards-home-new"].firstMatch
        for _ in 0..<3 where !newBoard.isHittable { app.swipeUp() }
        XCTAssertTrue(newBoard.appears(within: 5))
        newBoard.tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.appears(within: 5))
        let create = app.alerts.buttons["Create"].firstMatch
        XCTAssertFalse(create.isEnabled, "an empty name can't be created")
        field.tap()
        field.typeText("   ")
        XCTAssertFalse(create.isEnabled, "spaces aren't a name")
        field.typeText("Trips ")
        XCTAssertTrue(create.isEnabled)
        create.tap()
        let board = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'boards-home-' AND label CONTAINS 'Trips'")
        ).firstMatch
        XCTAssertTrue(board.appears(within: 5), "the trimmed name is created")
    }

    @MainActor
    func testSettingsShowStatusAndCapturePaths() throws {
        let app = try launch(["-force-free-tier"])
        defer { app.terminate() }
        app.buttons["Settings"].firstMatch.tap()
        let pro = app.buttons["open-pro"].firstMatch
        XCTAssertTrue(pro.appears(within: 5))
        XCTAssertTrue(pro.label.contains("Free ·"), pro.label)
        let keyboard = app.buttons["settings-keyboard-how"].firstMatch
        for _ in 0..<3 where !keyboard.isHittable { app.swipeUp() }
        keyboard.tap()
        XCTAssertTrue(app.navigationBars["Gancho keyboard"].appears(within: 5))
    }

    /// The switch lives in the App Group, so the test leaves it off as it found it.
    @MainActor
    func testKeyboardUpNextIsOffUntilTurnedOn() throws {
        let app = try launch(["-force-free-tier"])
        defer { app.terminate() }
        app.buttons["Settings"].firstMatch.tap()
        let toggle = app.switches["settings-keyboard-up-next"].firstMatch
        for _ in 0..<4 where !toggle.isHittable { app.swipeUp() }
        XCTAssertTrue(toggle.appears(within: 5))
        XCTAssertEqual(toggle.value as? String, "0", "off unless turned on")
        toggle.switches.firstMatch.tap()
        XCTAssertEqual(toggle.value as? String, "1")
        toggle.switches.firstMatch.tap()
        XCTAssertEqual(toggle.value as? String, "0")
    }

    @MainActor
    func testPrivacyCenterVerifiesEncryptionFirst() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-use-temp-durable-store", "-open-privacy-center-on-launch", "-AppleLanguages", "(en)"
        ]
        app.launch()
        defer { app.terminate() }
        let verify = app.buttons["ios-privacy-verify-encryption"].firstMatch
        XCTAssertTrue(verify.appears(within: 10))
        XCTAssertTrue(app.descendants(matching: .any)["ios-privacy-masked"].firstMatch.exists)
        verify.tap()
        let result = app.descendants(matching: .any)["ios-privacy-verify-result"].firstMatch
        XCTAssertTrue(result.appears(within: 10))
        // UI tests run on a plaintext throwaway store, so an honest check says so.
        XCTAssertEqual(result.label, "The database file isn’t encrypted.")
    }

    @MainActor
    private func expandSheet(in app: XCUIApplication) {
        let grabber = app.buttons["Sheet Grabber"].firstMatch
        guard grabber.appears(within: 5) else { return }
        grabber.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(
                forDuration: 0.1,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)))
    }

    @MainActor
    private func launch(_ extra: [String]) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments =
            [
                "-skip-welcome-on-launch", "-use-temp-durable-store", "-AppleLanguages", "(en)"
            ] + extra
        app.launch()
        guard
            app.descendants(matching: .any)["capture-screen"].firstMatch
                .appears(within: 10)
        else {
            app.terminate()
            throw XCTSkip("capture screen is not reachable on this runner")
        }
        return app
    }
}

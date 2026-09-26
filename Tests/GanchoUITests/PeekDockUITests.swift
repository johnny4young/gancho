import XCTest

final class PeekDockUITests: XCTestCase {
    @MainActor
    func testLinkKeepsExactURLAndDockInsideCompactPanel() throws {
        let app = launchPanel()
        defer { app.terminate() }
        let search = app.textFields["search-field"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        try SynthesizedInput.requireForeground(app)
        search.click()
        search.typeText("Synthetic link")
        let url = app.staticTexts["peek-link-url"].firstMatch
        XCTAssertTrue(url.waitForExistence(timeout: 5))
        let expected = "https://www.example.com:8443/a%2Fb?q=a%26b#section-2"
        XCTAssertTrue(url.label == expected || url.value as? String == expected)
        let panel = app.dialogs["history-panel"].firstMatch
        let dock = app.descendants(matching: .any)["peek-dock"].firstMatch
        XCTAssertTrue(panel.frame.contains(dock.frame))
        for id in ["preview-paste", "preview-paste-plain", "preview-pin", "preview-board"] {
            XCTAssertTrue(dock.buttons[id].firstMatch.isHittable, "\(id) must be a native button")
        }
        let edit = app.buttons["preview-edit-content"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5))
        edit.click()
        let editor = app.textViews["preview-content-field"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, expected)
        XCTAssertTrue(app.buttons["preview-cancel-content"].firstMatch.isHittable)
        XCTAssertTrue(panel.frame.contains(dock.frame), "Editing must not push the dock offscreen")
        app.buttons["preview-cancel-content"].firstMatch.click()
        attachPanel(panel, name: "Compact peek — complete URL and dock")
    }

    @MainActor
    func testPeekShortcutsRefreshBoardMembershipWithoutChangingSelection() throws {
        let app = launchPanel()
        defer { app.terminate() }
        let search = app.textFields["search-field"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        search.click()
        search.typeText("Synthetic link")
        XCTAssertTrue(app.staticTexts["peek-link-url"].firstMatch.waitForExistence(timeout: 5))
        try SynthesizedInput.requireForeground(app)
        app.typeKey(.rightArrow, modifierFlags: [])
        app.typeKey("p", modifierFlags: .command)
        let unpin = app.buttons["preview-pin"].firstMatch
        XCTAssertTrue(unpin.wait(for: \.label, toEqual: "Unpin", timeout: 5))
        app.typeKey("b", modifierFlags: .command)
        let picker = app.textFields["board-picker-filter"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5))
        XCTAssertTrue(SynthesizedInput.waitForKeyboardFocus(picker, timeout: 5))
        picker.typeText("Seed board 1")
        let board = app.descendants(matching: .any)["board-picker-board-row"].firstMatch
        XCTAssertTrue(board.waitForExistence(timeout: 5))
        board.click()
        let selected = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == 'Selected'"), object: board)
        XCTAssertEqual(XCTWaiter.wait(for: [selected], timeout: 5), .completed)
        picker.click()
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(picker.waitForNonExistence(timeout: 5))
        let chip = app.descendants(matching: .any).matching(
            NSPredicate(
                format:
                    "identifier BEGINSWITH 'peek-board-' AND (label CONTAINS %@ OR value CONTAINS %@)",
                "Seed board 1", "Seed board 1"
            )
        ).firstMatch
        XCTAssertTrue(
            chip.waitForExistence(timeout: 5), "The selected clip must refresh its boards")
        attachPanel(app.dialogs["history-panel"].firstMatch, name: "Peek — live board membership")
    }

    @MainActor
    func testReturnPastesFromPeekWithoutWritingTheClipboard() throws {
        let app = launchPanel()
        defer { app.terminate() }
        let search = app.textFields["search-field"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        try SynthesizedInput.requireForeground(app)
        search.click()
        search.typeText("Synthetic link")
        XCTAssertTrue(app.staticTexts["peek-link-url"].firstMatch.waitForExistence(timeout: 5))
        app.typeKey(.rightArrow, modifierFlags: [])
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.dialogs["history-panel"].firstMatch.waitForNonExistence(timeout: 5))
    }

    @MainActor
    func testCodePreviewRetainsReadableHeight() throws {
        let app = launchPanel()
        defer { app.terminate() }
        let search = app.textFields["search-field"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        try SynthesizedInput.requireForeground(app)
        search.click()
        search.typeText("Example")
        let preview = app.staticTexts["preview-content"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        XCTAssertTrue(preview.isHittable, "The nested preview must remain readable")
        XCTAssertGreaterThan(preview.frame.height, 10)
        let panel = app.dialogs["history-panel"].firstMatch
        XCTAssertTrue(
            panel.frame.contains(app.descendants(matching: .any)["peek-dock"].firstMatch.frame))
        attachPanel(panel, name: "Compact peek — code preview and dock")
    }

    @MainActor
    func testPrivateModeMasksTheSelectedHeroAndTitle() throws {
        let nonce = UUID().uuidString
        let app = launchPanel(extraArguments: ["-command-nonce", nonce])
        defer { app.terminate() }
        let search = app.textFields["search-field"].firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 15))
        try SynthesizedInput.requireForeground(app)
        search.click()
        search.typeText("Synthetic link")
        let url = app.staticTexts["peek-link-url"].firstMatch
        XCTAssertTrue(url.waitForExistence(timeout: 5))
        GanchoUITestCommands.post("togglePrivateMode", token: nonce)
        XCTAssertTrue(app.staticTexts["peek-masked"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(url.exists)
        let title = app.staticTexts["preview-title"].firstMatch
        XCTAssertFalse(title.label.contains("Synthetic link"))
        XCTAssertFalse((title.value as? String ?? "").contains("Synthetic link"))
        XCTAssertFalse(app.buttons["preview-edit-content"].firstMatch.exists)
        GanchoUITestCommands.post("togglePrivateMode", token: nonce)
        XCTAssertTrue(url.waitForExistence(timeout: 5))
    }

    @MainActor
    func testImageDockRemainsReachableInDarkCompactPanel() throws {
        let app = launchPanel(extraArguments: ["-appearance", "dark"])
        defer { app.terminate() }
        let images = app.buttons["filter-images"].firstMatch
        XCTAssertTrue(images.waitForExistence(timeout: 15))
        images.click()
        let landscape = app.descendants(matching: .any).matching(identifier: "clip-row")
            .matching(
                NSPredicate(format: "label BEGINSWITH 'image,' AND NOT (label CONTAINS %@)", "•••")
            ).firstMatch
        XCTAssertTrue(landscape.waitForExistence(timeout: 5))
        landscape.click()
        let title = app.staticTexts["preview-title"].firstMatch
        let named = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "label == %@ OR value == %@", "Synthetic landscape", "Synthetic landscape"),
            object: title)
        XCTAssertEqual(XCTWaiter.wait(for: [named], timeout: 5), .completed)
        let dock = app.descendants(matching: .any)["peek-dock"].firstMatch
        let panel = app.dialogs["history-panel"].firstMatch
        XCTAssertTrue(dock.waitForExistence(timeout: 5))
        XCTAssertTrue(panel.frame.contains(dock.frame))
        for id in [
            "preview-paste", "preview-paste-plain", "image-copy-text", "preview-pin",
            "preview-board"
        ] {
            XCTAssertTrue(dock.buttons[id].firstMatch.isHittable)
        }
        attachPanel(panel, name: "Compact dark peek — image and five-action dock")
    }

    @MainActor
    func testSensitiveImageDoesNotRevealItsTitleInPeek() throws {
        let app = launchPanel()
        defer { app.terminate() }
        let images = app.buttons["filter-images"].firstMatch
        XCTAssertTrue(images.waitForExistence(timeout: 15))
        images.click()
        let masked = app.descendants(matching: .any).matching(identifier: "clip-row")
            .matching(NSPredicate(format: "label CONTAINS %@", "•••")).firstMatch
        XCTAssertTrue(masked.waitForExistence(timeout: 5))
        masked.click()
        XCTAssertTrue(app.staticTexts["peek-masked"].firstMatch.waitForExistence(timeout: 5))
        let title = app.staticTexts["preview-title"].firstMatch
        XCTAssertFalse(title.label.contains("Hidden fixture title"))
        XCTAssertFalse((title.value as? String ?? "").contains("Hidden fixture title"))
        XCTAssertFalse(app.buttons["preview-edit-title"].firstMatch.exists)
        XCTAssertFalse(app.buttons["image-copy-text"].firstMatch.exists)
    }

    @MainActor
    private func launchPanel(extraArguments: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item", "-use-temp-durable-store",
            "-seed-visual-library", "-seed-sample-boards", "-force-free-tier",
            "-start-capture-paused",
            "-opaque-panel-for-ui-test", "-place-panel-for-ui-test",
            "-ui-test-paste-sink", "pasted",
            "-suppress-storage-notice-for-ui-test", "-AppleLanguages", "(en)",
            "-panel-content-width", "720", "-panel-content-height", "460", "-panel-text-size",
            "large",
            "-ui-test-defaults-suite", "com.johnny4young.gancho.uitests.peek.\(UUID().uuidString)"
        ]
        app.launchArguments += extraArguments
        app.launch()
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        return app
    }

    @MainActor
    private func attachPanel(_ panel: XCUIElement, name: String) {
        let attachment = XCTAttachment(screenshot: panel.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

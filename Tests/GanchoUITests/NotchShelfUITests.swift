import XCTest

/// The notch shelf, pinned open by a DEBUG flag: a clip dragged from the panel
/// lands on a board or runs an image action.
final class NotchShelfUITests: XCTestCase {
    @MainActor
    private func launch(extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = GanchoUITestApplication()
        app.launchArguments =
            extra + [
                "-open-panel-on-launch", "-use-in-process-status-item", "-use-temp-durable-store",
                "-seed-manual-ocr", "-seed-sample-boards", "-ui-test-open-notch-shelf",
                "-ui-test-keep-copy-hud", "-force-free-tier", "-start-capture-paused",
                "-suppress-paused-notice-for-ui-test", "-suppress-storage-notice-for-ui-test",
                "-ui-test-paste-sink", "copy-only", "-place-panel-for-ui-test",
                "-opaque-panel-for-ui-test", "-AppleLanguages", "(en)", "-appearance", "light",
                "-telemetry-consent", "disabled", "-ui-test-defaults-suite",
                "com.johnny4young.gancho.uitests.notch-shelf.\(UUID().uuidString)"
            ]
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 5)
        return app
    }

    @MainActor
    private func rows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "clip-row")
    }

    @MainActor
    /// The seeded image is the only clip.
    private func imageRow(_ app: XCUIApplication) -> XCUIElement {
        rows(app).firstMatch
    }

    @MainActor
    private func shelfBoard(_ name: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH 'notch-shelf-board-' AND label == %@", name)
        ).firstMatch
    }

    @MainActor
    private func action(_ id: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["notch-shelf-action-\(id)"].firstMatch
    }

    /// Slow, with a dwell over the target, so AppKit sees the drag enter it.
    @MainActor
    private func drag(_ source: XCUIElement, onto target: XCUIElement) {
        source.coordinate(withNormalizedOffset: CGVector(dx: 0.18, dy: 0.5)).press(
            forDuration: 1.0,
            thenDragTo: target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)),
            withVelocity: .default, thenHoldForDuration: 0.8)
    }

    /// A macOS static text carries its string as the value.
    @MainActor
    private func hudTitle(_ app: XCUIApplication) -> String {
        let element = app.descendants(matching: .any)["copy-hud"].firstMatch
        return (element.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? element.label
    }

    @MainActor
    private func waitForHUD(_ title: String, in app: XCUIApplication) -> Bool {
        let deadline = Date().addingTimeInterval(15)
        repeat {
            if hudTitle(app) == title { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline
        return false
    }

    @MainActor
    private func toastSays(_ text: String, in app: XCUIApplication) -> Bool {
        let toast = app.descendants(matching: .any)["gancho-toast"].firstMatch
        let deadline = Date().addingTimeInterval(8)
        repeat {
            let texts =
                toast.exists
                ? toast.staticTexts.allElementsBoundByIndex.map {
                    $0.label.isEmpty ? $0.value as? String ?? "" : $0.label
                } : []
            if texts.contains(text) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline
        return false
    }

    @MainActor
    func testShelfShowsBoardsAndActions() throws {
        let app = launch()
        defer { app.terminate() }
        XCTAssertTrue(
            app.descendants(matching: .any)["notch-shelf"].firstMatch.appears(
                within: 10))
        for index in 1...3 {
            XCTAssertTrue(shelfBoard("Seed board \(index)", in: app).appears(within: 5))
        }
        for id in ["extract-text", "resize", "strip-location", "new-board"] {
            XCTAssertTrue(action(id, in: app).exists, id)
        }
        try keepRender(of: "notch-shelf-zone", in: app, named: "Notch shelf")
    }

    @MainActor
    func testDroppingAClipOnAShelfBoardFilesIt() throws {
        let app = launch()
        defer { app.terminate() }
        let row = imageRow(app)
        XCTAssertTrue(row.appears(within: 15))
        let board = shelfBoard("Seed board 2", in: app)
        XCTAssertTrue(board.appears(within: 10))
        try SynthesizedInput.requireForeground(app)

        drag(row, onto: board)
        XCTAssertTrue(toastSays("Added to Seed board 2", in: app))
    }

    /// Extract text saves the recognized text as a new clip and copies it.
    @MainActor
    func testExtractTextFromADroppedImage() throws {
        let app = launch()
        defer { app.terminate() }
        let row = imageRow(app)
        XCTAssertTrue(row.appears(within: 15))
        XCTAssertEqual(rows(app).count, 1)
        let extract = action("extract-text", in: app)
        XCTAssertTrue(extract.appears(within: 10))
        try SynthesizedInput.requireForeground(app)

        drag(row, onto: extract)
        XCTAssertTrue(waitForHUD("Text extracted · Copied", in: app), hudTitle(app))
        let text = rows(app).matching(NSPredicate(format: "label CONTAINS %@", "Hola Gancho"))
        XCTAssertTrue(text.firstMatch.appears(within: 10))
    }

    /// The seeded image is 640 px wide, so Resize hands it back as it is.
    @MainActor
    func testResizeNeverEnlarges() throws {
        let app = launch()
        defer { app.terminate() }
        let row = imageRow(app)
        XCTAssertTrue(row.appears(within: 15))
        let resize = action("resize", in: app)
        XCTAssertTrue(resize.appears(within: 10))
        try SynthesizedInput.requireForeground(app)

        drag(row, onto: resize)
        XCTAssertTrue(waitForHUD("Already 1280 px or smaller · Copied", in: app), hudTitle(app))
    }

    /// Private Mode refuses the drop: nothing is filed.
    @MainActor
    func testPrivateModeRefusesDrops() throws {
        let nonce = UUID().uuidString
        let app = launch(extra: ["-command-nonce", nonce])
        defer { app.terminate() }
        let row = imageRow(app)
        XCTAssertTrue(row.appears(within: 15))
        let board = shelfBoard("Seed board 1", in: app)
        XCTAssertTrue(board.appears(within: 10))
        GanchoUITestCommands.post("togglePrivateMode", token: nonce)
        try SynthesizedInput.requireForeground(app)

        drag(row, onto: board)
        XCTAssertFalse(toastSays("Added to Seed board 1", in: app))
    }

    /// A screen share refuses the drop too. Toasts and the HUD hide while
    /// sharing, so the proof is that no recognized-text clip is saved.
    @MainActor
    func testScreenShareRefusesDrops() throws {
        let app = launch(extra: ["-simulate-screen-share", "Zoom"])
        defer { app.terminate() }
        let row = imageRow(app)
        XCTAssertTrue(row.appears(within: 15))
        let extract = action("extract-text", in: app)
        XCTAssertTrue(extract.appears(within: 10))
        try SynthesizedInput.requireForeground(app)

        drag(row, onto: extract)
        let text = rows(app).matching(NSPredicate(format: "label CONTAINS %@", "Hola Gancho"))
        XCTAssertFalse(text.firstMatch.appears(within: 8))
        XCTAssertEqual(rows(app).count, 1)
    }

    @MainActor
    func testCaptureSettingsOfferTheShelf() throws {
        let app = try launchSettingsWindow(extraArguments: [
            "-use-temp-durable-store", "-start-capture-paused", "-appearance", "light",
            "-ui-test-defaults-suite",
            "com.johnny4young.gancho.uitests.notch-shelf-settings.\(UUID().uuidString)"
        ])
        defer { app.terminate() }
        app.buttons["settings-tab-capture"].firstMatch.click()
        let toggle = app.descendants(matching: .any)["settings-notch-shelf"].firstMatch
        XCTAssertTrue(toggle.appears(within: 5))
        XCTAssertEqual(toggle.value as? Int, 0)
        let form = app.scrollViews.containing(.any, identifier: "settings-notch-shelf").firstMatch
        XCTAssertTrue(toggle.revealByScrolling(in: form))
        try keepRender(of: "Settings", in: app, named: "Capture settings notch shelf")
        try SynthesizedInput.requireForeground(app)
        toggle.click()
        XCTAssertEqual(toggle.value as? Int, 1)
    }
}

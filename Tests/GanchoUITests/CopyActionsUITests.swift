import XCTest

/// With copy actions on, a color, a web link or a one-time code just copied
/// gets a HUD with its actions.
final class CopyActionsUITests: XCTestCase {
    @MainActor
    private func launch(
        seeding kind: String, appearance: String = "light", extra: [String] = []
    ) -> GanchoUITestApplication {
        let app = GanchoUITestApplication()
        app.launchArguments =
            extra + [
                "-open-panel-on-launch", "-use-in-process-status-item", "-use-temp-durable-store",
                "-seed-copy-actions", kind, "-ui-test-keep-copy-hud", "-force-free-tier",
                "-start-capture-paused", "-ui-test-paste-sink", "copy-only",
                "-opaque-panel-for-ui-test", "-place-panel-for-ui-test", "-AppleLanguages", "(en)",
                "-suppress-storage-notice-for-ui-test", "-telemetry-consent", "disabled",
                "-panel-content-width", "720", "-panel-content-height", "460",
                "-appearance", appearance, "-ui-test-defaults-suite",
                "com.johnny4young.gancho.uitests.copy-actions.\(UUID().uuidString)"
            ]
        app.launch()
        return app
    }

    @MainActor
    private func hud(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["copy-hud"].firstMatch
    }

    /// A macOS static text carries its string as the value.
    @MainActor
    private func title(_ app: XCUIApplication) -> String {
        let element = hud(app)
        return (element.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? element.label
    }

    @MainActor
    func testColorOffersFormats() throws {
        let app = launch(seeding: "color")
        defer { app.terminate() }
        XCTAssertTrue(hud(app).waitForExistence(timeout: 10))
        XCTAssertTrue(title(app).contains("Color · #008080"), title(app))
        XCTAssertTrue(app.buttons["copy-hud-action-rgb"].exists)
        XCTAssertTrue(app.buttons["copy-hud-action-hsl"].exists)
        try keepRender(of: "copy-hud-panel", in: app, named: "Color HUD")
    }

    @MainActor
    func testLinkOffersOpen() throws {
        let app = launch(seeding: "link")
        defer { app.terminate() }
        XCTAssertTrue(hud(app).waitForExistence(timeout: 10))
        XCTAssertTrue(title(app).contains("Link · gancho.app"), title(app))
        XCTAssertTrue(app.buttons["copy-hud-action-open"].exists)
        try keepRender(of: "copy-hud-panel", in: app, named: "Link HUD")
    }

    /// The HUD holds while hovered, so it watches for Private Mode itself.
    @MainActor
    func testPrivateModeHidesAVisibleHUD() throws {
        let nonce = UUID().uuidString
        let app = launch(seeding: "color", extra: ["-command-nonce", nonce])
        defer { app.terminate() }
        XCTAssertTrue(hud(app).waitForExistence(timeout: 10))
        GanchoUITestCommands.post("togglePrivateMode", token: nonce)
        XCTAssertTrue(hud(app).waitForNonexistence(timeout: 5))
    }

    /// The code stays masked, and Forget now removes its clip from history.
    @MainActor
    func testOneTimeCodeIsMaskedAndForgetRemovesIt() throws {
        let app = launch(seeding: "code")
        defer { app.terminate() }
        XCTAssertTrue(hud(app).waitForExistence(timeout: 10))
        XCTAssertTrue(title(app).hasPrefix("One-time code"), title(app))
        XCTAssertFalse(title(app).contains("482"), "the code never shows")
        let rows = app.descendants(matching: .any).matching(identifier: "clip-row")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, 1)
        try keepRender(of: "copy-hud-panel", in: app, named: "One-time code HUD")

        let forget = app.buttons["copy-hud-action-forget"].firstMatch
        XCTAssertTrue(forget.exists)
        forget.click()
        XCTAssertTrue(rows.firstMatch.waitForNonexistence(timeout: 5))
        XCTAssertTrue(hud(app).waitForExistence(timeout: 5))
        XCTAssertEqual(title(app), "Forgotten")
    }

    /// The switch lives in Settings › Capture, starts off, and offers one
    /// switch per kind once on.
    @MainActor
    func testCaptureSettingsOfferTheSwitches() throws {
        let app = try launchSettingsWindow(extraArguments: [
            "-use-temp-durable-store", "-start-capture-paused", "-appearance", "light",
            "-ui-test-defaults-suite",
            "com.johnny4young.gancho.uitests.copy-actions-settings.\(UUID().uuidString)"
        ])
        defer { app.terminate() }
        app.buttons["settings-tab-capture"].firstMatch.click()
        let toggle = app.descendants(matching: .any)["settings-copy-actions"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? Int, 0)
        let form = app.scrollViews.containing(.any, identifier: "settings-copy-actions").firstMatch
        XCTAssertTrue(toggle.revealByScrolling(in: form))
        let colors = app.descendants(matching: .any)["settings-copy-actions-colors"].firstMatch
        XCTAssertFalse(colors.exists)

        try SynthesizedInput.requireForeground(app)
        toggle.click()
        XCTAssertTrue(colors.waitForExistence(timeout: 5))
        for id in ["colors", "links", "codes"] {
            let kind = app.descendants(matching: .any)["settings-copy-actions-\(id)"].firstMatch
            XCTAssertEqual(kind.value as? Int, 1, id)
        }
        let codes = app.descendants(matching: .any)["settings-copy-actions-codes"].firstMatch
        XCTAssertTrue(codes.revealByScrolling(in: form))
        form.scroll(byDeltaX: 0, deltaY: -400)
        try keepRender(of: "Settings", in: app, named: "Capture settings copy actions")
    }
}

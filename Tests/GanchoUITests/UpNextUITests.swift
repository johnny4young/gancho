import XCTest

/// Up next: the clip pasted most into the app in front sits above the list,
/// ⌘↩ pastes it, and it steps aside while searching.
final class UpNextUITests: XCTestCase {
    @MainActor func testLight() throws { try verify(dark: false) }
    @MainActor func testDark() throws { try verify(dark: true) }

    @MainActor
    private func verify(dark: Bool) throws {
        continueAfterFailure = false
        let nonce = UUID().uuidString
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item", "-use-temp-durable-store",
            "-seed-up-next", "-ui-test-up-next-target", "com.example.editor",
            "-ui-test-paste-target", "Editor", "-ui-test-paste-sink", "pasted",
            "-force-free-tier", "-start-capture-paused", "-command-nonce", nonce,
            "-opaque-panel-for-ui-test", "-place-panel-for-ui-test", "-AppleLanguages", "(en)",
            "-appearance", dark ? "dark" : "light", "-telemetry-consent", "disabled",
            "-suppress-storage-notice-for-ui-test",
            "-panel-content-width", "720", "-panel-content-height", "460",
            "-ui-test-defaults-suite",
            "com.johnny4young.gancho.uitests.upnext.\(UUID().uuidString)"
        ]
        app.launch()
        defer { app.terminate() }
        try SynthesizedInput.requireForeground(app)

        let slot = app.descendants(matching: .any)["up-next-slot"].firstMatch
        XCTAssertTrue(slot.waitForExistence(timeout: 10))
        XCTAssertTrue(slot.label.contains("Greeting"), slot.label)
        XCTAssertTrue(reason(of: slot).contains("Pasted into Editor"), reason(of: slot))
        XCTAssertTrue(reason(of: slot).contains("3×"), reason(of: slot))
        let firstRow = app.descendants(matching: .any).matching(identifier: "clip-row").firstMatch
        XCTAssertFalse(firstRow.label.contains("Greeting"), "the slot is not the first row")
        try keepRender(of: "history-panel", in: app, named: "Up next — \(dark ? "dark" : "light")")

        let search = app.textFields["search-field"].firstMatch
        try typeTextReliably("seed", into: search, in: app)
        XCTAssertTrue(slot.waitForNonExistence(timeout: 5), "searching hides Up next")
        search.typeKey("a", modifierFlags: .command)
        search.typeKey(.delete, modifierFlags: [])
        XCTAssertTrue(slot.waitForExistence(timeout: 5), "clearing the search brings it back")

        app.typeKey(.return, modifierFlags: .command)
        let panel = app.descendants(matching: .any)["history-panel"].firstMatch
        XCTAssertTrue(panel.waitForNonExistence(timeout: 5), "⌘↩ pastes and closes the panel")
        GanchoUITestCommands.post("openPanel", token: nonce)
        XCTAssertTrue(slot.waitForExistence(timeout: 10))
        let counted = NSPredicate { _, _ in self.reason(of: slot).contains("4×") }
        XCTAssertEqual(
            XCTWaiter.wait(
                for: [XCTNSPredicateExpectation(predicate: counted, object: nil)], timeout: 5),
            .completed, "the ⌘↩ paste of the predicted clip is logged: \(reason(of: slot))")
    }

    /// Turning Up next off in Intelligence erases the paste log: on again, the
    /// seeded habit is gone.
    @MainActor
    func testTurningItOffErasesTheLog() throws {
        let nonce = UUID().uuidString
        let app = try launchSettingsWindow(extraArguments: [
            "-use-temp-durable-store", "-start-capture-paused", "-seed-up-next",
            "-ui-test-up-next-target", "com.example.editor", "-command-nonce", nonce,
            "-opaque-panel-for-ui-test", "-place-panel-for-ui-test",
            "-ui-test-defaults-suite",
            "com.johnny4young.gancho.uitests.upnext-off.\(UUID().uuidString)"
        ])
        defer { app.terminate() }
        let slot = app.descendants(matching: .any)["up-next-slot"].firstMatch
        GanchoUITestCommands.post("openPanel", token: nonce)
        XCTAssertTrue(slot.waitForExistence(timeout: 10), "the seeded habit predicts")
        app.typeKey(.escape, modifierFlags: [])

        app.buttons["settings-tab-capture"].firstMatch.click()
        let openIntelligence = app.buttons["open-intelligence"].firstMatch
        XCTAssertTrue(openIntelligence.waitForExistence(timeout: 3))
        openIntelligence.click()
        let toggle = app.windows["Intelligence"].firstMatch
            .descendants(matching: .any)["intelligence-toggle-up-next"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? Int, 1)
        toggle.click()
        XCTAssertEqual(toggle.value as? Int, 0)
        toggle.click()
        XCTAssertEqual(toggle.value as? Int, 1)

        GanchoUITestCommands.post("openPanel", token: nonce)
        let panel = app.descendants(matching: .any)["history-panel"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 10))
        XCTAssertFalse(slot.waitForExistence(timeout: 3), "the log was erased with the switch")
    }

    /// The slot's value carries the reason line.
    @MainActor
    private func reason(of slot: XCUIElement) -> String {
        slot.value as? String ?? ""
    }
}

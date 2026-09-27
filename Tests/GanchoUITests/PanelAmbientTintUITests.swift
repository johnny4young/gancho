import XCTest

/// The ambient-colour preference: off by default, one toggle in Settings ›
/// Panel, remembered across relaunch, and the panel keeps working with it on.
final class PanelAmbientTintUITests: XCTestCase {
    @MainActor
    func testAmbientColorToggleIsOffByDefaultAndPersists() throws {
        let suite = "com.johnny4young.gancho.uitests.panel-ambient-\(UUID().uuidString)"
        let settingsURL = try XCTUnwrap(URL(string: "gancho://settings"))
        let commandToken = UUID().uuidString
        let persistenceArguments = [
            "-ui-test-defaults-suite", suite,
            "-force-ephemeral-store", "-seed-sample-clips", "-opaque-panel-for-ui-test",
            "-place-panel-for-ui-test",
            "-suppress-storage-notice-for-ui-test", "-AppleLanguages", "(en)"
        ]
        let settingsArguments = [
            "-regular-activation-for-ui-tests", "-use-in-process-status-item",
            "-command-nonce", commandToken,
            "-open-deep-link-on-launch", settingsURL.absoluteString
        ]

        var app: XCUIApplication = GanchoUITestApplication()
        app.launchArguments = settingsArguments + persistenceArguments
        app.launch()
        XCTAssertTrue(app.windows["Settings"].firstMatch.waitForExistence(timeout: 5))

        let toggle = app.switches["panel-ambient-tint"].firstMatch
        XCTAssertTrue(
            toggle.waitForExistence(timeout: 5), "the Panel section must offer Ambient color")
        XCTAssertEqual(switchState(toggle), 0, "ambient colour is opt-in")
        // Bring the app forward first: a click on a background window can be
        // spent on activation. The window itself may sit on another display,
        // so only the switch is clicked, never the window.
        app.activate()
        try SynthesizedInput.requireForeground(app)
        toggle.click()
        if !waitForSwitch(toggle, toBe: 1) {
            toggle.click()
        }
        XCTAssertTrue(waitForSwitch(toggle, toBe: 1), "the click must switch ambient colour on")

        GanchoUITestCommands.post("openPanel", token: commandToken)
        let panel = app.descendants(matching: .any)["history-panel"].firstMatch
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        let rows = app.descendants(matching: .any).matching(identifier: "clip-row")
        XCTAssertTrue(
            rows.firstMatch.waitForExistence(timeout: 10),
            "the panel must still list clips with the wash behind them")
        XCTAssertTrue(app.textFields["search-field"].firstMatch.exists)
        // The first row is selected on open; a click would hand key focus back
        // and forth with the Settings window and can hide the panel.
        let evidence = XCTAttachment(screenshot: panel.screenshot())
        evidence.name = "History panel — ambient colour on"
        evidence.lifetime = .keepAlways
        add(evidence)

        app.terminate()
        app = GanchoUITestApplication()
        app.launchArguments =
            settingsArguments + persistenceArguments + ["-preserve-ui-test-defaults"]
        app.launch()
        defer { app.terminate() }
        let relaunched = app.switches["panel-ambient-tint"].firstMatch
        XCTAssertTrue(relaunched.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForSwitch(relaunched, toBe: 1), "the choice must survive relaunch")
    }

    /// The AX snapshot can lag the click by a frame; poll rather than read once.
    @MainActor
    private func waitForSwitch(_ element: XCUIElement, toBe state: Int) -> Bool {
        let deadline = Date().addingTimeInterval(3)
        while Date() < deadline {
            if switchState(element) == state { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return switchState(element) == state
    }

    /// A grouped-form Toggle is an AX switch whose value arrives as a number or
    /// its string, depending on the bridge.
    @MainActor
    private func switchState(_ element: XCUIElement) -> Int? {
        (element.value as? Int) ?? (element.value as? String).flatMap(Int.init)
    }
}

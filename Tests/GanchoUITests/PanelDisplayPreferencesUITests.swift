import AppKit
import XCTest

/// Focused persistence and visual evidence for user-controlled panel display
/// preferences. Kept separate from the keyboard/navigation smoke suite so each
/// UI test class stays small and owns one stable workflow.
final class PanelDisplayPreferencesUITests: XCTestCase {
    @MainActor
    func testPanelSizeAndTextSizePersistAcrossRelaunch() throws {
        let suite = "com.johnny4young.gancho.uitests.panel-display-\(UUID().uuidString)"
        let settingsURL = try XCTUnwrap(URL(string: "gancho://settings"))
        let panelURL = try XCTUnwrap(URL(string: "gancho://panel"))
        let persistenceArguments = [
            "-ui-test-defaults-suite", suite,
            "-force-ephemeral-store", "-seed-sample-clips", "-opaque-panel-for-ui-test",
            "-suppress-storage-notice-for-ui-test"
        ]
        let settingsArguments = [
            "-regular-activation-for-ui-tests", "-use-in-process-status-item",
            "-open-deep-link-on-launch", settingsURL.absoluteString
        ]

        var app = XCUIApplication()
        app.launchArguments = settingsArguments + persistenceArguments
        app.launch()
        waitForAppToStart(app)
        XCTAssertTrue(app.windows["Settings"].firstMatch.waitForExistence(timeout: 5))

        XCTAssertTrue(NSWorkspace.shared.open(panelURL))
        let panel = historyPanel(in: app)
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        XCTAssertEqual(panel.value as? String, "standard")

        try SynthesizedInput.requireForeground(app)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(
            waitUntil { !panel.exists }, "Escape must hide the panel before editing Settings")
        app.windows["Settings"].firstMatch.click()

        let largeSize = app.buttons["panel-size-large"].firstMatch
        XCTAssertTrue(largeSize.waitForExistence(timeout: 3))
        largeSize.click()

        // SwiftUI's segmented Picker is exposed as a RadioGroup on macOS.
        let textSize = app.radioGroups["panel-text-size"].firstMatch
        XCTAssertTrue(textSize.waitForExistence(timeout: 3))
        textSize.radioButtons["Large"].click()

        XCTAssertTrue(NSWorkspace.shared.open(panelURL))
        XCTAssertTrue(panel.waitForExistence(timeout: 5))
        XCTAssertTrue(
            waitUntil { panel.frame.width >= 1_060 },
            "the Large preset must resize the live panel")
        XCTAssertEqual(
            panel.value as? String, "large",
            "Large text must update the panel's semantic text scale live")
        XCTAssertFalse(
            app.descendants(matching: .any)["capture-notice"].firstMatch.exists,
            "the synthetic screenshot flow must not render an expected storage warning")

        let screenshot = XCTAttachment(screenshot: panel.screenshot())
        screenshot.name = "panel-large-text"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.terminate()
        app = launchWithPanel(
            extraArguments: persistenceArguments + ["-preserve-ui-test-defaults"])
        defer { app.terminate() }
        let relaunchedPanel = historyPanel(in: app)
        XCTAssertTrue(relaunchedPanel.waitForExistence(timeout: 5))
        XCTAssertEqual(relaunchedPanel.value as? String, "large")
        XCTAssertTrue(
            waitUntil { relaunchedPanel.frame.width >= 1_060 },
            "the chosen panel size must survive relaunch")
    }

    @MainActor
    private func launchWithPanel(extraArguments: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-open-panel-on-launch", "-use-in-process-status-item"]
        app.launchArguments += extraArguments
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
    private func waitUntil(
        timeout: TimeInterval = 5,
        pollInterval: TimeInterval = 0.1,
        _ condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(pollInterval))
        }
        return condition()
    }

    @MainActor
    private func historyPanel(in app: XCUIApplication) -> XCUIElement {
        // NSPanel is exposed as a Dialog rather than a Window on macOS 26.
        app.descendants(matching: .any)["history-panel"].firstMatch
    }
}

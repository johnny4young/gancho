import XCTest

/// Before/after numbers for the paths the design phases touch: panel open
/// (request → first frame) and paste dispatch, read from the app's own
/// content-free signposts. Search over 100k rows stays in `make bench`.
/// Runs only through `make bench-ui` (`GANCHO_PERF=1`); wall-clock budgets
/// never gate the regular suites.
final class PerformanceBaselineUITests: XCTestCase {
    private func metric(_ name: String) -> XCTOSSignpostMetric {
        XCTOSSignpostMetric(subsystem: "com.johnny4young.gancho", category: "perf", name: name)
    }

    override func setUpWithError() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["GANCHO_PERF"] == "1",
            "performance baselines run only via make bench-ui")
    }

    @MainActor func testPanelOpenToFirstFrame() throws {
        let (app, token) = launch()
        defer { app.terminate() }
        let panel = app.descendants(matching: .any)["history-panel"].firstMatch
        let search = app.textFields["search-field"].firstMatch
        let options = XCTMeasureOptions()
        options.iterationCount = 10
        measure(metrics: [metric("panel-to-first-frame")], options: options) {
            GanchoUITestCommands.post("openPanel", token: token)
            XCTAssertTrue(panel.waitForExistence(timeout: 5))
            // The panel is non-activating, so the app is never "frontmost";
            // keys go only to a search field that holds keyboard focus.
            guard SynthesizedInput.waitForKeyboardFocus(search, timeout: 5) else {
                return XCTFail("search field never took keyboard focus")
            }
            search.typeKey(.escape, modifierFlags: [])
            XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
        }
    }

    @MainActor func testPasteDispatch() throws {
        let (app, token) = launch()
        defer { app.terminate() }
        let panel = app.descendants(matching: .any)["history-panel"].firstMatch
        let rows = app.descendants(matching: .any).matching(identifier: "clip-row")
        let search = app.textFields["search-field"].firstMatch
        let options = XCTMeasureOptions()
        options.iterationCount = 10
        measure(metrics: [metric("paste-dispatch")], options: options) {
            GanchoUITestCommands.post("openPanel", token: token)
            XCTAssertTrue(panel.waitForExistence(timeout: 5))
            XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
            guard SynthesizedInput.waitForKeyboardFocus(search, timeout: 5) else {
                return XCTFail("search field never took keyboard focus")
            }
            search.typeKey(.return, modifierFlags: [])
            XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
        }
    }

    @MainActor private func launch() -> (XCUIApplication, String) {
        let token = UUID().uuidString
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-regular-activation-for-ui-tests", "-use-in-process-status-item",
            "-command-nonce", token, "-has-seen-welcome", "YES",
            "-use-temp-durable-store", "-seed-source-apps", "-start-capture-paused",
            "-opaque-panel-for-ui-test", "-suppress-storage-notice-for-ui-test",
            // Paste-back writes nothing and posts no ⌘V anywhere.
            "-ui-test-paste-sink", "pasted",
            "-AppleLanguages", "(en)",
            "-ui-test-defaults-suite", "com.johnny4young.gancho.uitests.perf.\(token)"
        ]
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 8)
        return (app, token)
    }
}

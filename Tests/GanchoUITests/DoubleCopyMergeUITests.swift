import XCTest

/// A double copy appends to the clip before it: the history keeps one clip
/// holding both parts, and the first copy's own clip is gone.
final class DoubleCopyMergeUITests: XCTestCase {
    @MainActor
    func testDoubleCopyAppendsToThePreviousClip() throws {
        continueAfterFailure = false
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item", "-use-temp-durable-store",
            "-seed-double-copy", "-force-free-tier", "-start-capture-paused",
            "-ui-test-paste-sink", "copy-only",
            "-opaque-panel-for-ui-test", "-place-panel-for-ui-test", "-AppleLanguages", "(en)",
            "-suppress-storage-notice-for-ui-test", "-telemetry-consent", "disabled",
            "-panel-content-width", "720", "-panel-content-height", "460",
            "-ui-test-defaults-suite",
            "com.johnny4young.gancho.uitests.double-copy.\(UUID().uuidString)"
        ]
        app.launch()
        defer { app.terminate() }

        let rows = app.descendants(matching: .any).matching(identifier: "clip-row")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(rows.count, 1, "the first copy's clip was dropped")
        let label = rows.firstMatch.label
        XCTAssertTrue(label.contains("Ana Restrepo"), label)
        XCTAssertTrue(label.contains("Cra. 43A"), label)
        try keepRender(of: "history-panel", in: app, named: "Double copy merged")
    }

    /// The switch lives in Settings › Capture and starts off.
    @MainActor
    func testCaptureSettingsOfferTheSwitchOff() throws {
        let app = try launchSettingsWindow(extraArguments: [
            "-use-temp-durable-store", "-start-capture-paused",
            "-ui-test-defaults-suite",
            "com.johnny4young.gancho.uitests.double-copy-settings.\(UUID().uuidString)"
        ])
        defer { app.terminate() }
        app.buttons["settings-tab-capture"].firstMatch.click()
        let toggle = app.descendants(matching: .any)["settings-merge-double-copies"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? Int, 0)
        let form = app.scrollViews.containing(.any, identifier: "settings-merge-double-copies")
            .firstMatch
        XCTAssertTrue(toggle.revealByScrolling(in: form))
        try keepRender(of: "Settings", in: app, named: "Capture settings")
    }
}

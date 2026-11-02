import XCTest

/// A double copy appends to the clip before it: the history keeps one clip
/// holding both parts, and the first copy's own clip is gone.
final class DoubleCopyMergeUITests: XCTestCase {
    @MainActor
    private func launchMerged(extra: [String] = []) -> GanchoUITestApplication {
        let app = GanchoUITestApplication()
        app.launchArguments =
            [
                "-open-panel-on-launch", "-use-in-process-status-item", "-use-temp-durable-store",
                "-seed-double-copy", "-force-free-tier", "-start-capture-paused",
                "-ui-test-paste-sink", "copy-only",
                "-opaque-panel-for-ui-test", "-place-panel-for-ui-test", "-AppleLanguages",
                "(en)",
                "-suppress-storage-notice-for-ui-test", "-telemetry-consent", "disabled",
                "-panel-content-width", "720", "-panel-content-height", "460",
                "-appearance", "light", "-ui-test-defaults-suite",
                "com.johnny4young.gancho.uitests.double-copy.\(UUID().uuidString)"
            ] + extra
        app.launch()
        return app
    }

    @MainActor
    func testDoubleCopyAppendsToThePreviousClip() throws {
        continueAfterFailure = false
        let app = launchMerged(extra: ["-ui-test-keep-copy-hud"])
        defer { app.terminate() }

        let rows = app.descendants(matching: .any).matching(identifier: "clip-row")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(rows.count, 1, "the first copy's clip was dropped")
        let label = rows.firstMatch.label
        XCTAssertTrue(label.contains("Ana Restrepo"), label)
        XCTAssertTrue(label.contains("Cra. 43A"), label)
        let hud = app.descendants(matching: .any)["copy-hud"].firstMatch
        XCTAssertTrue(hud.waitForExistence(timeout: 5))
        XCTAssertTrue(hud.label.contains("Merged · 2 parts"), hud.label)
        XCTAssertFalse(
            app.descendants(matching: .any)["gancho-toast"].exists, "the HUD replaces the toast")
        try keepRender(of: "history-panel", in: app, named: "Double copy merged")
        try keepRender(of: "copy-hud-panel", in: app, named: "Merged HUD")
    }

    /// The peek shows each part; a separator chip re-joins them and Split
    /// turns them back into separate clips.
    @MainActor
    func testMergedPeekChangesTheSeparatorAndSplits() throws {
        continueAfterFailure = false
        let app = launchMerged()
        app.activate()
        defer { app.terminate() }

        let rows = app.descendants(matching: .any).matching(identifier: "clip-row")
        guard rows.firstMatch.waitForExistence(timeout: 10), rows.firstMatch.isHittable else {
            throw XCTSkip("seeded panel row is not reachable on this runner")
        }
        rows.firstMatch.click()
        let parts = app.descendants(matching: .any).matching(identifier: "peek-part")
        XCTAssertTrue(parts.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(parts.count, 2)
        let newline = app.descendants(matching: .any)["peek-separator-newline"].firstMatch
        XCTAssertTrue(newline.isSelected)
        try keepRender(of: "history-panel", in: app, named: "Merged peek")

        try SynthesizedInput.requireForeground(app)
        app.descendants(matching: .any)["peek-separator-comma"].firstMatch.click()
        let commaRow = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier == 'clip-row' AND label CONTAINS %@",
                "Ana Restrepo, Cra. 43A")
        ).firstMatch
        XCTAssertTrue(commaRow.waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.descendants(matching: .any)["peek-separator-comma"].firstMatch.isSelected)
        try keepRender(of: "history-panel", in: app, named: "Merged peek comma")

        try SynthesizedInput.requireForeground(app)
        app.buttons["peek-split-parts"].firstMatch.click()
        let first = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == 'clip-row' AND label CONTAINS %@", "Ana Restrepo")
        )
        let expected = NSPredicate(format: "count == 2")
        expectation(for: expected, evaluatedWith: rows)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(first.count, 1)
        XCTAssertFalse(first.firstMatch.label.contains("Cra. 43A"), "the merged clip is gone")
    }

    /// The switch lives in Settings › Capture and starts off; turning it on
    /// offers the sound, which starts on.
    @MainActor
    func testCaptureSettingsOfferTheSwitchOff() throws {
        let app = try launchSettingsWindow(extraArguments: [
            "-use-temp-durable-store", "-start-capture-paused", "-appearance", "light",
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
        let sound = app.descendants(matching: .any)["settings-merge-sound"].firstMatch
        XCTAssertFalse(sound.exists)
        try keepRender(of: "Settings", in: app, named: "Capture settings")

        try SynthesizedInput.requireForeground(app)
        toggle.click()
        XCTAssertTrue(sound.waitForExistence(timeout: 5))
        XCTAssertEqual(sound.value as? Int, 1)
        try keepRender(of: "Settings", in: app, named: "Capture settings merging on")
    }
}

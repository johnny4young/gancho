import XCTest

/// A secret's peek: the ticked dial, a bordered reveal and a plain Delete.
extension DesignV4SnapshotUITests {
    @MainActor func testPanelSecretPeekLight() throws {
        try secretPeek(appearance: "light")
    }

    @MainActor func testPanelSecretPeekDark() throws {
        try secretPeek(appearance: "dark")
    }

    @MainActor private func secretPeek(appearance: String) throws {
        let app = GanchoUITestApplication()
        app.launchArguments =
            stableArguments(appearance) + [
                "-open-panel-on-launch", "-use-in-process-status-item", "-seed-peek-secret",
                "-force-free-tier", "-suppress-paused-notice-for-ui-test",
                "-opaque-panel-for-ui-test", "-place-panel-for-ui-test",
                "-suppress-storage-notice-for-ui-test", "-ui-test-paste-target", "Terminal",
                "-AppleLanguages", "(en)"
            ]
        app.launch()
        defer { app.terminate() }
        let row = app.descendants(matching: .any).matching(identifier: "clip-row")
            .matching(NSPredicate(format: "label BEGINSWITH 'secret,'")).firstMatch
        XCTAssertTrue(row.appears(within: 15))
        try SynthesizedInput.requireForeground(app)
        row.click()
        let countdown = app.descendants(matching: .any)["peek-secret-countdown"].firstMatch
        XCTAssertTrue(countdown.appears(within: 5))
        // The seed expires 9:30 after launch; capture just inside 9:15 so the
        // clock and its ring read the same on every run.
        let deadline = Date().addingTimeInterval(30)
        while countdown.label != "Self-destructs in 9:16", Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertEqual(countdown.label, "Self-destructs in 9:16")
        RunLoop.current.run(until: Date().addingTimeInterval(1.1))
        try DesignSnapshot.save(
            DesignSnapshot.renderWindow(titled: "Gancho", named: "panel", in: renders),
            named: "panel-secret-peek-\(appearance)")
    }
}

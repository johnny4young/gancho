import AppKit
import XCTest

extension DesignV4SnapshotUITests {
    // MARK: ⌘K — the action panel over the code clip's peek.

    @MainActor func testPanelActionPanelLight() throws {
        try actionPanel(appearance: "light")
    }

    @MainActor func testPanelActionPanelDark() throws {
        try actionPanel(appearance: "dark")
    }

    @MainActor private func actionPanel(appearance: String) throws {
        let app = GanchoUITestApplication()
        app.launchArguments =
            stableArguments(appearance) + [
                "-open-panel-on-launch", "-use-in-process-status-item", "-seed-visual-library",
                "-force-free-tier", "-opaque-panel-for-ui-test", "-place-panel-for-ui-test",
                "-suppress-storage-notice-for-ui-test", "-suppress-paused-notice-for-ui-test",
                "-ui-test-paste-target", "Xcode", "-ui-test-paste-sink", "pasted",
                "-AppleLanguages", "(en)"
            ]
        app.launch()
        defer { app.terminate() }
        // The code clip is the newest seed, so it is selected on open.
        let code = app.descendants(matching: .any).matching(identifier: "clip-row")
            .matching(NSPredicate(format: "label BEGINSWITH %@", "code,")).firstMatch
        XCTAssertTrue(code.appears(within: 8))
        try SynthesizedInput.requireForeground(app)
        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(
            app.descendants(matching: .any)["transform-popover"].firstMatch.appears(within: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        try DesignSnapshot.save(
            DesignSnapshot.renderWindow(titled: "Gancho", named: "panel", in: renders),
            named: "panel-action-panel-\(appearance)")
    }
}

import AppKit
import XCTest

extension DesignV4SnapshotUITests {
    // MARK: The paste stack in the peek, before a run starts.

    @MainActor func testPanelPasteStackLight() throws {
        try pasteStack(appearance: "light")
    }

    @MainActor func testPanelPasteStackDark() throws {
        try pasteStack(appearance: "dark")
    }

    @MainActor private func pasteStack(appearance: String) throws {
        let app = GanchoUITestApplication()
        app.launchArguments =
            stableArguments(appearance) + [
                "-open-panel-on-launch", "-use-in-process-status-item", "-seed-visual-library",
                "-seed-paste-stack", "-force-free-tier", "-opaque-panel-for-ui-test",
                "-place-panel-for-ui-test", "-suppress-storage-notice-for-ui-test",
                "-suppress-paused-notice-for-ui-test", "-ui-test-paste-target", "Xcode",
                "-ui-test-paste-sink", "pasted", "-AppleLanguages", "(en)",
                // The board's size; the content's minimum height makes the window 492 pt.
                "-panel-content-width", "864", "-panel-content-height", "480"
            ]
        app.launch()
        defer { app.terminate() }
        let strip = app.buttons["paste-stack-strip"].firstMatch
        XCTAssertTrue(strip.appears(within: 15))
        try SynthesizedInput.requireForeground(app)
        strip.click()
        XCTAssertTrue(
            app.descendants(matching: .any)["peek-paste-stack"].firstMatch.appears(within: 5))
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        try DesignSnapshot.save(
            DesignSnapshot.renderWindow(titled: "Gancho", named: "panel", in: renders),
            named: "panel-paste-stack-\(appearance)")
    }
}

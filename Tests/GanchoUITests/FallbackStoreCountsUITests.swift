import XCTest

/// Without the durable store, the panel still counts what it lists.
final class FallbackStoreCountsUITests: XCTestCase {
    @MainActor func testAllClipsChipCountsTheFallbackStoreLight() throws {
        try checkAllClipsCount(appearance: "light")
    }

    @MainActor func testAllClipsChipCountsTheFallbackStoreDark() throws {
        try checkAllClipsCount(appearance: "dark")
    }

    @MainActor
    private func checkAllClipsCount(appearance: String) throws {
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item", "-force-ephemeral-store",
            "-seed-sample-clips", "-force-free-tier", "-start-capture-paused",
            "-place-panel-for-ui-test", "-appearance", appearance, "-AppleLanguages", "(en)",
            "-ui-test-defaults-suite",
            "com.johnny4young.gancho.uitests.fallback-counts.\(UUID().uuidString)"
        ]
        app.launch()
        defer { app.terminate() }
        let all = app.buttons["board-all"].firstMatch
        XCTAssertTrue(all.waitForExistence(timeout: 15))
        let counted = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "All clips · 3"), object: all)
        let result = XCTWaiter.wait(for: [counted], timeout: 5)
        // Rendered before the assertion, so a run without the count still shows the panel.
        try keepRender(
            of: "history-panel", in: app, named: "Fallback store All clips count \(appearance)")
        XCTAssertEqual(result, .completed, "the chip reads \(all.label)")
    }
}

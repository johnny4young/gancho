import XCTest

final class IntentionalCaptureUITests: XCTestCase {
    @MainActor
    func testDirectCaptureRefusesMarkerOnSecondPasteboardItem() throws {
        try assertRefused("protected-direct")
    }

    @MainActor
    func testProviderCaptureRefusesMarkerOnSiblingProvider() throws {
        try assertRefused("protected-provider")
    }

    @MainActor
    func testSafeTextProviderReportsDurableSuccess() throws {
        try assertSaved("safe-text")
    }

    @MainActor
    func testSafeImageProviderReportsDurableSuccess() throws {
        try assertSaved("safe-image")
    }

    @MainActor
    private func assertRefused(_ scenario: String) throws {
        let app = launch(scenario)
        defer { app.terminate() }
        let note = app.descendants(matching: .any).matching(identifier: "save-note").firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 10))
        XCTAssertTrue(note.label.contains("cannot be saved for privacy reasons"))
        // Absence only means something after giving a late insert time to land.
        XCTAssertFalse(
            app.descendants(matching: .any).matching(identifier: "clip-row").firstMatch
                .waitForExistence(timeout: 3))
    }

    @MainActor
    private func assertSaved(_ scenario: String) throws {
        let app = launch(scenario)
        defer { app.terminate() }
        let note = app.descendants(matching: .any).matching(identifier: "save-note").firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 10))
        XCTAssertTrue(note.label.contains("Saved"))
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "clip-row").firstMatch
                .waitForExistence(timeout: 10))
    }

    @MainActor
    private func launch(_ scenario: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-skip-welcome-on-launch", "-use-temp-durable-store",
            "-seed-intentional-capture", scenario, "-ui-test-save-note-lifetime", "30",
            "-force-free-tier", "-AppleLanguages", "(en)"
        ]
        app.launch()
        return app
    }
}

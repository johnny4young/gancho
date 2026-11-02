import XCTest

/// "Describe the change": a request in words, the rewrite as a word diff, and
/// a saved prompt that comes back in the Transform list. The model is a fixed
/// UI-test stand-in.
final class DescribeChangeUITests: XCTestCase {
    @MainActor func testLight() throws { try verify(dark: false) }
    @MainActor func testDark() throws { try verify(dark: true) }

    @MainActor
    private func verify(dark: Bool) throws {
        continueAfterFailure = false
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item", "-use-temp-durable-store",
            "-seed-clip-editing", "-ui-test-describe-change", "-force-free-tier",
            "-start-capture-paused", "-ui-test-paste-sink", "copy-only",
            "-opaque-panel-for-ui-test", "-place-panel-for-ui-test", "-AppleLanguages", "(en)",
            "-appearance", dark ? "dark" : "light", "-telemetry-consent", "disabled",
            "-panel-content-width", "720", "-panel-content-height", "640",
            "-ui-test-defaults-suite",
            "com.johnny4young.gancho.uitests.describe.\(UUID().uuidString)"
        ]
        app.launch()
        defer { app.terminate() }
        try SynthesizedInput.requireForeground(app)
        let row = app.descendants(matching: .any).matching(identifier: "clip-row").firstMatch
        XCTAssertTrue(row.waitForHittable(timeout: 10))
        row.click()

        let transform = app.buttons["transform-button"].firstMatch
        XCTAssertTrue(transform.waitForExistence(timeout: 5))
        transform.click()
        let describe = app.buttons["transform-row-describe-change"].firstMatch
        XCTAssertTrue(describe.waitForExistence(timeout: 5))
        describe.click()

        let field = app.textFields["describe-change-field"].firstMatch
        try typeTextReliably("Say ship", into: field, in: app)
        app.typeKey(.return, modifierFlags: [])
        let willPaste = app.descendants(matching: .any)["describe-change-will-paste"].firstMatch
        XCTAssertTrue(willPaste.waitForExistence(timeout: 5), "the rewrite shows as a diff")
        XCTAssertTrue(
            app.staticTexts.containing(
                NSPredicate(format: "value CONTAINS 'ship' OR label CONTAINS 'ship'")
            )
            .firstMatch.exists)

        try keepRender(
            of: "history-panel", in: app,
            named: "Describe the change — synthetic — \(dark ? "dark" : "light")")
        let save = app.buttons["describe-change-save-prompt"].firstMatch
        save.click()
        XCTAssertTrue(save.waitForNonExistence(timeout: 5), "a saved prompt drops its Save button")
        transform.click()
        XCTAssertTrue(
            app.buttons["transform-row-prompt-Say ship"].firstMatch.waitForExistence(timeout: 5),
            "a saved prompt comes back in the Transform list")
    }
}

import XCTest

/// The shared paste sequence, driven from the real panel. The app runs with a
/// paste sink (`-ui-test-paste-sink`), so these tests never replace the
/// developer's clipboard or post ⌘V into another app, and they choose the
/// Accessibility answer instead of inheriting whatever this Mac has granted.
final class PasteBackUITests: XCTestCase {
    private static let copyOnlyNotice = "Copied — enable Accessibility to paste directly"

    @MainActor
    private func launchSeededPanel(pasteSink answer: String) -> XCUIApplication {
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item",
            "-force-ephemeral-store", "-seed-sample-clips",
            "-ui-test-paste-sink", answer,
            "-telemetry-consent", "disabled", "-AppleLanguages", "(en)"
        ]
        app.launch()
        return app
    }

    /// Double-clicks the first seeded row, a plain paste, and returns the panel.
    /// The panel is asserted on screen first: without that, its disappearance
    /// afterwards would prove nothing.
    @MainActor
    private func pasteFirstRow(in app: XCUIApplication) throws -> XCUIElement {
        let row = app.descendants(matching: .any).matching(identifier: "clip-row").firstMatch
        guard row.waitForExistence(timeout: 10), row.isHittable else {
            throw XCTSkip("seeded panel row is not reachable on this runner")
        }
        // NSPanel is exposed as a Dialog rather than a Window on macOS 26.
        let panel = app.descendants(matching: .any)["history-panel"].firstMatch
        XCTAssertTrue(panel.exists, "the panel must be on screen before the paste")
        try SynthesizedInput.requireForeground(app)
        row.doubleClick()
        return panel
    }

    @MainActor
    func testCopyOnlyPasteHidesThePanelAndOffersAccessibility() throws {
        let app = launchSeededPanel(pasteSink: "copied-only")
        defer { app.terminate() }
        let panel = try pasteFirstRow(in: app)

        XCTAssertTrue(
            panel.waitForNonExistence(timeout: 5),
            "pasting must hide the panel so focus can return to the target app")
        let toast = app.descendants(matching: .any)["gancho-toast"].firstMatch
        XCTAssertTrue(toast.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[Self.copyOnlyNotice].exists)
        // The Enable action is offered but deliberately NOT clicked: it opens
        // System Settings.
        XCTAssertTrue(app.buttons["toast-action"].firstMatch.exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "macOS copy-only paste notice"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testPostedPasteHidesThePanelWithoutTheAccessibilityNotice() throws {
        let app = launchSeededPanel(pasteSink: "pasted")
        defer { app.terminate() }
        let panel = try pasteFirstRow(in: app)

        XCTAssertTrue(panel.waitForNonExistence(timeout: 5))
        XCTAssertFalse(
            app.staticTexts[Self.copyOnlyNotice].waitForExistence(timeout: 2),
            "a posted paste has nothing to warn about")
    }
}

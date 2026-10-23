import XCTest

/// The v4 panel's behaviour: the paste target the dock and footer name, the
/// footer's capture chip, and the timed Private Mode.
final class PanelBehaviourUITests: XCTestCase {
    @MainActor
    private func launch(capturing: Bool, extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = GanchoUITestApplication()
        app.launchArguments =
            [
                "-open-panel-on-launch", "-use-in-process-status-item", "-use-temp-durable-store",
                "-seed-visual-library", "-force-free-tier", "-opaque-panel-for-ui-test",
                "-place-panel-for-ui-test", "-suppress-storage-notice-for-ui-test",
                "-force-pasteboard-access-allowed", "-disable-screen-share-auto-pause",
                "-isolate-ui-test-system-clipboard", "-AppleLanguages", "(en)",
                "-ui-test-defaults-suite",
                "com.johnny4young.gancho.uitests.behaviour.\(UUID().uuidString)"
            ] + (capturing ? ["-force-capture-active"] : ["-start-capture-paused"]) + extra
        app.launch()
        return app
    }

    @MainActor
    private func waitFor(_ element: XCUIElement, label: String) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", label), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 10) == .completed
    }

    /// macOS static text reports its string as the value, not the label.
    @MainActor
    private func text(beginningWith prefix: String, in root: XCUIElement) -> XCUIElement {
        root.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH[c] %@ OR value BEGINSWITH[c] %@", prefix, prefix)
        ).firstMatch
    }

    @MainActor
    func testDockAndFooterNameTheAppInFront() throws {
        let app = launch(
            capturing: true,
            extra: ["-ui-test-paste-target", "Figma", "-ui-test-paste-sink", "pasted"])
        defer { app.terminate() }
        let paste = app.buttons["preview-paste"].firstMatch
        XCTAssertTrue(paste.waitForExistence(timeout: 15))
        XCTAssertTrue(waitFor(paste, label: "Paste into Figma"), paste.label)

        let chip = app.descendants(matching: .any)["capture-indicator"].firstMatch
        XCTAssertTrue(waitFor(chip, label: "Capturing · Figma in front"), chip.label)
    }

    @MainActor
    func testDockSaysCopyWithoutAccessibility() throws {
        let app = launch(
            capturing: false,
            extra: ["-ui-test-paste-target", "Figma", "-ui-test-paste-sink", "copy-only"])
        defer { app.terminate() }
        let paste = app.buttons["preview-paste"].firstMatch
        XCTAssertTrue(paste.waitForExistence(timeout: 15))
        XCTAssertTrue(waitFor(paste, label: "Copy"), paste.label)

        let chip = app.descendants(matching: .any)["capture-indicator"].firstMatch
        XCTAssertTrue(waitFor(chip, label: "Capture paused"), chip.label)
    }

    @MainActor
    func testPrivateModeIsIndigoTimedAndTurnsOff() throws {
        let nonce = UUID().uuidString
        let app = launch(capturing: true, extra: ["-command-nonce", nonce])
        defer { app.terminate() }
        let chip = app.descendants(matching: .any)["capture-indicator"].firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 15))
        GanchoUITestCommands.post("togglePrivateMode", token: nonce)

        XCTAssertTrue(waitFor(chip, label: "Private mode · 60 min left"), chip.label)
        let notice = app.descendants(matching: .any)["capture-notice"].firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 5))
        XCTAssertTrue(text(beginningWith: "Private Mode is on · since ", in: notice).exists)
        XCTAssertTrue(
            text(beginningWith: "0 copies skipped, none read · turns off at ", in: notice).exists)
        XCTAssertTrue(text(beginningWith: "Before private mode", in: app).exists)

        let turnOff = app.buttons["private-mode-turn-off"].firstMatch
        XCTAssertTrue(turnOff.exists)
        try SynthesizedInput.requireForeground(app)
        turnOff.click()
        XCTAssertTrue(waitFor(chip, label: "Capturing"), chip.label)
        XCTAssertFalse(notice.exists)
    }
}

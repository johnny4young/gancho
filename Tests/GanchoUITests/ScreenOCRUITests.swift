import AppKit
import XCTest

final class ScreenOCRUITests: XCTestCase {
    @MainActor
    func testSensitiveScreenResultRequiresRevealBeforeEditingOrCopying() throws {
        let nonce = UUID().uuidString
        let app = launchApp(
            nonce: nonce, permissionArgument: "-screen-ocr-sensitive-result-for-ui-test")
        defer { app.terminate() }
        let rows = app.descendants(matching: .any).matching(identifier: "clip-row")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 15))
        GanchoUITestCommands.post("copyScreenText", token: nonce)
        let review = app.buttons["ocr-review"].firstMatch
        XCTAssertTrue(review.waitForExistence(timeout: 5))
        review.click()
        let reveal = app.buttons["ocr-review-reveal"].firstMatch
        XCTAssertTrue(reveal.waitForExistence(timeout: 5))
        let editor = app.textViews["ocr-review-text"].firstMatch
        XCTAssertFalse(editor.exists, "Masked text must not enter the accessibility tree")
        XCTAssertFalse(app.buttons["ocr-review-copy"].exists)
        XCTAssertFalse(app.buttons["ocr-review-save"].exists)
        let masked = XCTAttachment(
            screenshot: app.windows["Review recognized text"].firstMatch.screenshot())
        masked.name = "Screen OCR — sensitive review before reveal"
        masked.lifetime = .keepAlways
        add(masked)
        reveal.click()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        XCTAssertEqual(editor.value as? String, "card 4242 4242 4242 4242")
        XCTAssertTrue(app.buttons["ocr-review-copy"].isEnabled)
        XCTAssertTrue(app.buttons["ocr-review-save"].isEnabled)
        app.buttons["ocr-review-hide"].click()
        XCTAssertTrue(editor.waitForNonexistence(timeout: 5))
        XCTAssertFalse(app.buttons["ocr-review-copy"].exists)
        app.buttons["ocr-review-close"].click()
        // The toast may have dismissed the transient panel before Review opened.
        GanchoUITestCommands.post("openPanel", token: nonce)
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(rows.count, 1, "Reviewing a secret must not save it")
    }

    @MainActor
    func testStatusMenuOffersScreenCapture() throws {
        let app = launchApp(
            nonce: UUID().uuidString, permissionArgument: "-screen-ocr-denied-for-ui-test")
        defer { app.terminate() }
        let statusItem = app.statusItems.firstMatch
        XCTAssertTrue(statusItem.waitForExistence(timeout: 5))
        guard statusItem.isHittable else {
            throw XCTSkip("status item is not hittable on this display/Space")
        }
        try SynthesizedInput.requireForeground(app)
        statusItem.click()
        let command = app.menuItems["Copy text from screen"].firstMatch
        XCTAssertTrue(command.waitForExistence(timeout: 3))
        command.click()
        XCTAssertTrue(app.buttons["Open Settings"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(app.descendants(matching: .any)["screen-ocr-selector"].exists)
    }

    @MainActor
    func testDeniedScreenCaptureStillAllowsSavedImageOCR() throws {
        let nonce = UUID().uuidString
        let app = launchApp(nonce: nonce, permissionArgument: "-screen-ocr-denied-for-ui-test")
        defer { app.terminate() }
        let row = app.descendants(matching: .any).matching(identifier: "clip-row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        GanchoUITestCommands.post("copyScreenText", token: nonce)
        XCTAssertTrue(app.buttons["Open Settings"].firstMatch.waitForExistence(timeout: 5))
        try SynthesizedInput.requireForeground(app)
        row.rightClick()
        let extract = app.menuItems["image-copy-text"].firstMatch
        XCTAssertTrue(extract.waitForExistence(timeout: 3))
        extract.click()
        let line = app.descendants(matching: .any).matching(identifier: "peek-ocr-line-0")
            .firstMatch
        XCTAssertTrue(line.waitForExistence(timeout: 15))
        XCTAssertFalse(app.descendants(matching: .any)["screen-ocr-selector"].exists)
    }

    @MainActor
    func testCancellingPurposeExplanationDoesNotShowDeniedGuidance() throws {
        let nonce = UUID().uuidString
        let app = launchApp(nonce: nonce, permissionArgument: "-screen-ocr-purpose-for-ui-test")
        defer { app.terminate() }
        let rows = app.descendants(matching: .any).matching(identifier: "clip-row")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 15))
        GanchoUITestCommands.post("copyScreenText", token: nonce)
        let explanation = app.staticTexts["Copy screen text privately"].firstMatch
        XCTAssertTrue(explanation.waitForExistence(timeout: 5))
        let cancel = app.buttons["Cancel"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 3))
        try SynthesizedInput.requireForeground(app)
        cancel.click()
        XCTAssertTrue(explanation.waitForNonexistence(timeout: 5))
        XCTAssertFalse(app.buttons["Open Settings"].firstMatch.exists)
        XCTAssertFalse(app.buttons["ocr-review"].firstMatch.exists)
        XCTAssertFalse(app.descendants(matching: .any)["screen-ocr-selector"].exists)
        XCTAssertEqual(rows.count, 1)
    }

    @MainActor
    func testSelectorClosesOnEscapeAndEmptyClickAndCanReopen() throws {
        let nonce = UUID().uuidString
        let app = launchApp(nonce: nonce, permissionArgument: "-screen-ocr-selector-for-ui-test")
        defer { app.terminate() }
        let rows = app.descendants(matching: .any).matching(identifier: "clip-row")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 15))
        try SynthesizedInput.requireForeground(app)
        let selectors = app.descendants(matching: .any).matching(identifier: "screen-ocr-selector")
        for cancelWithEscape in [true, false, true] {
            GanchoUITestCommands.post("copyScreenText", token: nonce)
            let selector = selectors.firstMatch
            XCTAssertTrue(selector.waitForExistence(timeout: 5))
            try SynthesizedInput.requireForeground(app)
            if cancelWithEscape {
                app.typeKey(.escape, modifierFlags: [])
            } else {
                selector.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
            }
            XCTAssertTrue(selector.waitForNonexistence(timeout: 5))
            XCTAssertFalse(app.buttons["ocr-review"].firstMatch.exists)
            XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 5))
            XCTAssertEqual(rows.count, 1)
        }
    }

    @MainActor
    func testPrivateModeCancelsSelectionAndResumeDoesNotReviveIt() throws {
        let nonce = UUID().uuidString
        let app = launchApp(nonce: nonce, permissionArgument: "-screen-ocr-selector-for-ui-test")
        defer { app.terminate() }
        let row = app.descendants(matching: .any).matching(identifier: "clip-row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        let selector = app.descendants(matching: .any)["screen-ocr-selector"].firstMatch
        GanchoUITestCommands.post("copyScreenText", token: nonce)
        XCTAssertTrue(selector.waitForExistence(timeout: 5))
        GanchoUITestCommands.post("togglePrivateMode", token: nonce)
        XCTAssertTrue(selector.waitForNonexistence(timeout: 5))
        GanchoUITestCommands.post("togglePrivateMode", token: nonce)
        XCTAssertFalse(selector.waitForExistence(timeout: 1))
        XCTAssertFalse(app.buttons["ocr-review"].firstMatch.exists)
        GanchoUITestCommands.post("copyScreenText", token: nonce)
        XCTAssertTrue(selector.waitForExistence(timeout: 5))
        try SynthesizedInput.requireForeground(app)
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(selector.waitForNonexistence(timeout: 5))
    }

    @MainActor
    private func launchApp(nonce: String, permissionArgument: String) -> XCUIApplication {
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item", "-use-temp-durable-store",
            "-place-panel-for-ui-test",
            "-seed-manual-ocr", "-force-free-tier", "-start-capture-paused",
            "-ui-test-paste-sink", "copiedOnly", permissionArgument,
            "-ui-test-defaults-suite", "com.johnny4young.gancho.uitests.screen.\(UUID())",
            "-command-nonce", nonce, "-AppleLanguages", "(en)"
        ]
        app.launch()
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        return app
    }
}

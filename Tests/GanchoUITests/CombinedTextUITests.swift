import AppKit
import XCTest

final class CombinedTextUITests: XCTestCase {
    @MainActor
    func testReviewCancelAndCopyDoNotCreateClips() throws {
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item", "-use-temp-durable-store",
            "-seed-source-apps", "-force-free-tier", "-start-capture-paused",
            "-opaque-panel-for-ui-test", "-suppress-storage-notice-for-ui-test",
            "-ui-test-paste-sink", "copiedOnly", "-AppleLanguages", "(en)",
            "-ui-test-defaults-suite", "com.johnny4young.gancho.uitests.combined.\(UUID())"
        ]
        app.launch()
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        defer { app.terminate() }
        let rows = app.descendants(matching: .any).matching(identifier: "clip-row")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 15))
        let count = rows.count
        XCTAssertGreaterThanOrEqual(count, 3)
        try SynthesizedInput.requireForeground(app)
        rows.element(boundBy: 0).click()
        XCUIElement.perform(withKeyModifiers: .command) {
            rows.element(boundBy: 2).click()
        }
        XCTAssertFalse(
            app.windows["SafariPlatformSupportAutoCompleteWindow"].exists,
            "search completion must not obscure the multi-selection controls")
        let combined = app.buttons["selection-copy-combined-button"]
        XCTAssertTrue(combined.waitForExistence(timeout: 5))
        combined.click()
        let preview = app.descendants(matching: .any)["combined-text-preview"].firstMatch
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
        let expectedText = "Xcode source sample\n\nSafari source alpha"
        XCTAssertTrue(preview.staticTexts[expectedText].waitForExistence(timeout: 5))
        let copy = app.buttons["combined-text-copy"]
        XCTAssertTrue(copy.waitForHittable(timeout: 5))
        XCTAssertTrue(copy.isEnabled)
        app.buttons["Cancel"].firstMatch.click()
        XCTAssertTrue(preview.waitForNonExistence(timeout: 5))
        XCTAssertEqual(rows.count, count)
        combined.click()
        XCTAssertTrue(preview.staticTexts[expectedText].waitForExistence(timeout: 5))
        XCTAssertTrue(copy.waitForHittable(timeout: 5))
        XCTAssertTrue(copy.isEnabled)
        let attachment = XCTAttachment(
            screenshot: app.dialogs["history-panel"].firstMatch.screenshot())
        attachment.name = "Combined text review — synthetic source clips"
        attachment.lifetime = .keepAlways
        add(attachment)
        copy.click()
        XCTAssertTrue(preview.waitForNonExistence(timeout: 5))
        XCTAssertEqual(rows.count, count)
    }
}

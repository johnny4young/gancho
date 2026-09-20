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
            "-ui-test-paste-sink", "copy-only", "-AppleLanguages", "(en)",
            "-ui-test-defaults-suite", "com.johnny4young.gancho.uitests.combined.\(UUID())"
        ]
        app.launch()
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        defer { app.terminate() }
        let rows = app.descendants(matching: .any).matching(identifier: "clip-row")
        // The seed inserts its three clips from a fire-and-forget task, so the
        // first row can exist while the rest are still landing. Wait for the
        // last seeded row before snapshotting the count this test compares
        // against later, or the snapshot races the seed.
        XCTAssertTrue(rows.element(boundBy: 2).waitForExistence(timeout: 15))
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
        // The preview is read-only: ⌘C over it must neither select nor copy
        // anything (no second write path around the Copy button), and the
        // sheet stays put.
        app.typeKey("c", modifierFlags: .command)
        XCTAssertTrue(preview.staticTexts[expectedText].exists)
        XCTAssertTrue(copy.isEnabled)
        XCTAssertEqual(rows.count, count)
        app.buttons["combined-text-cancel"].firstMatch.click()
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

import XCTest

/// Settings › Retention: the timeline follows the pickers, and "Forget recent
/// clips" counts first, then forgets through the panel's undoable delete.
final class RetentionSettingsUITests: XCTestCase {
    @MainActor
    private func openRetention() throws -> XCUIApplication {
        let app = try launchSettingsWindow(extraArguments: [
            "-use-temp-durable-store", "-seed-visual-library", "-start-capture-paused",
            "-ui-test-defaults-suite",
            "com.johnny4young.gancho.uitests.retention.\(UUID().uuidString)"
        ])
        let tab = app.windows["Settings"].buttons["settings-tab-retention"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 3))
        tab.click()
        XCTAssertTrue(
            app.descendants(matching: .any)["retention-timeline"].firstMatch
                .waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    private func marker(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "retention-marker")
            .matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", label, label))
            .firstMatch
    }

    @MainActor
    func testChangingImagesMovesItsMarker() throws {
        let app = try openRetention()
        defer { app.terminate() }
        XCTAssertTrue(marker("secrets", in: app).exists)
        XCTAssertFalse(marker("images", in: app).exists, "Use global folds images in")
        let images = app.popUpButtons["retention-images-picker"].firstMatch
        XCTAssertTrue(images.waitForExistence(timeout: 3))
        images.click()
        app.menuItems["7 days"].firstMatch.click()
        XCTAssertTrue(marker("7 d · images", in: app).waitForExistence(timeout: 3))

        // Five markers still read: no label sits on another.
        let text = app.popUpButtons["retention-text-picker"].firstMatch
        text.click()
        app.menuItems["90 days"].firstMatch.click()
        XCTAssertTrue(marker("text", in: app).waitForExistence(timeout: 3))
        let frames = app.descendants(matching: .any).matching(identifier: "retention-marker")
            .allElementsBoundByIndex.map(\.frame)
        XCTAssertEqual(frames.count, 5)
        for (index, frame) in frames.enumerated() {
            for other in frames.dropFirst(index + 1) {
                XCTAssertFalse(frame.insetBy(dx: 1, dy: 1).intersects(other), "\(frame) \(other)")
            }
        }
    }

    @MainActor
    func testForgetRecentCountsThenForgetsAndUndoBringsThemBack() throws {
        let app = try openRetention()
        defer { app.terminate() }
        let count = app.descendants(matching: .any)["forget-recent-count"].firstMatch
        func shows(_ text: String) -> XCTNSPredicateExpectation {
            XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "label == %@ OR value == %@", text, text),
                object: count)
        }
        XCTAssertEqual(
            XCTWaiter.wait(for: [shows("4 clips")], timeout: 8), .completed, "the seed is 4 clips")
        app.buttons["forget-recent-button"].firstMatch.click()
        XCTAssertEqual(XCTWaiter.wait(for: [shows("Nothing to forget")], timeout: 5), .completed)
        let undo = app.buttons["toast-undo"].firstMatch
        XCTAssertTrue(undo.waitForExistence(timeout: 3))
        undo.click()
        XCTAssertEqual(
            XCTWaiter.wait(for: [shows("4 clips")], timeout: 5), .completed, "Undo restores them")
    }
}

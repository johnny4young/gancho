import XCTest

final class ImageTextUITests: XCTestCase {
    @MainActor
    func testOpeningAnImageReadsItsLinesAndHoldsTheSecretBack() throws {
        let app = try launchSeededApp()
        defer { app.terminate() }

        app.descendants(matching: .any).matching(identifier: "clip-row").firstMatch.tap()
        let copyImage = app.buttons["detail-copy"].firstMatch
        XCTAssertTrue(copyImage.waitForExistence(timeout: 5))
        XCTAssertEqual(copyImage.label, "Copy image")
        XCTAssertTrue(
            app.descendants(matching: .any)["detail-ocr-region-4"].firstMatch
                .waitForExistence(timeout: 60), "recognition never finished")
        for line in 1...4 {
            XCTAssertTrue(
                app.descendants(matching: .any)["detail-ocr-region-\(line)"].firstMatch.exists,
                "region \(line)")
        }
        // The rows sit under Copy: raise the sheet, then scroll to them.
        let secretLine = app.descendants(matching: .any)["detail-ocr-line-4"].firstMatch
        drag(app, from: 0.85, to: 0.3)
        for _ in 0..<3 where !(secretLine.exists && secretLine.isHittable) {
            drag(app, from: 0.8, to: 0.55)
        }
        XCTAssertTrue(secretLine.waitForExistence(timeout: 2))
        XCTAssertFalse(app.descendants(matching: .any)["detail-ocr-line-5"].firstMatch.exists)
        XCTAssertFalse(secretLine.label.contains("AKIA"), "the key must start masked")
        XCTAssertFalse(app.descendants(matching: .any)["detail-ocr-translate"].firstMatch.exists)

        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label == 'Open gancho.app'")).firstMatch
                .exists, "the link line offers its link")
        let copyAll = app.buttons["detail-ocr-copy-all"].firstMatch
        XCTAssertTrue(copyAll.label.contains("3"), copyAll.label)
        app.buttons["detail-ocr-reveal-4"].firstMatch.tap()
        XCTAssertTrue(
            app.buttons["detail-ocr-copy-line-4"].firstMatch.waitForExistence(timeout: 2))
        XCTAssertTrue(copyAll.label.contains("4"), copyAll.label)
    }

    @MainActor
    func testSaveLeavesTheHeldLineOut() throws {
        let app = try launchSeededApp()
        defer { app.terminate() }

        app.descendants(matching: .any).matching(identifier: "clip-row").firstMatch.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)["detail-ocr-region-4"].firstMatch
                .waitForExistence(timeout: 60), "recognition never finished")
        drag(app, from: 0.85, to: 0.3)
        let save = app.buttons["detail-ocr-save"].firstMatch
        for _ in 0..<4 where !(save.exists && save.isHittable) {
            drag(app, from: 0.8, to: 0.55)
        }
        save.tap()
        app.buttons["Done"].firstMatch.tap()
        let saved = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == 'clip-row' AND label CONTAINS 'Hola Gancho'")
        ).firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5), "the saved text clip")
        XCTAssertFalse(saved.label.contains("AKIA"), saved.label)
    }

    /// Raises the detail sheet, then scrolls it, by screen fraction.
    @MainActor
    private func drag(_ app: XCUIApplication, from start: CGFloat, to end: CGFloat) {
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: start)).press(
            forDuration: 0.05,
            thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: end)))
    }

    @MainActor
    private func launchSeededApp() throws -> XCUIApplication {
        let app = XCUIApplication()
        for _ in 0..<2 {
            app.terminate()
            app.launchArguments = [
                "-skip-welcome-on-launch", "-use-temp-durable-store", "-seed-image-text",
                "-force-free-tier", "-AppleLanguages", "(en)"
            ]
            app.launch()
            let row = app.descendants(matching: .any).matching(identifier: "clip-row").firstMatch
            if row.waitForExistence(timeout: 8) { return app }
        }
        return try XCTUnwrap(
            nil as XCUIApplication?,
            "the isolated image-text fixture did not become available after one retry")
    }
}

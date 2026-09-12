import XCTest

final class ManualOCRUITests: XCTestCase {
    @MainActor
    func testFreeManualOCRWithAutomaticOCRDisabled() throws {
        let app = launchOCR(language: "en", appearance: "dark")
        defer { app.terminate() }
        let text = try openReview(in: app)
        XCTAssertTrue((text.value as? String)?.contains("Hola Gancho") == true)
        XCTAssertTrue((text.value as? String)?.contains("Texto de una imagen") == true)
        attach(app.windows["Review recognized text"], named: "Manual OCR — English dark review")
        app.buttons["ocr-review-copy"].click()
        XCTAssertTrue(text.waitForNonExistence(timeout: 5))
        XCTAssertEqual(rows(in: app).count, 1, "Copying OCR must not create another history clip")
    }

    @MainActor
    func testSpanishReviewEditsAndSavesOnlyOnRequest() throws {
        let app = launchOCR(language: "es", appearance: "light")
        defer { app.terminate() }
        var text = try openReview(in: app)
        XCTAssertEqual(app.buttons["ocr-review-copy"].label, "Copiar texto")
        XCTAssertEqual(app.buttons["ocr-review-save"].label, "Guardar como clip")
        try typeTextReliably("Texto editado: canción y café", into: text, in: app)
        attach(app.windows["Revisar texto reconocido"], named: "Manual OCR — Spanish light review")
        app.buttons["ocr-review-close"].click()
        XCTAssertTrue(text.waitForNonExistence(timeout: 5))
        XCTAssertEqual(rows(in: app).count, 1, "Closing an edited review must not save a clip")
        text = try openReview(in: app)
        try typeTextReliably("Texto editado: canción y café", into: text, in: app)
        app.buttons["ocr-review-save"].click()
        XCTAssertTrue(text.waitForNonExistence(timeout: 5))
        let count = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count == 2"), object: rows(in: app))
        XCTAssertEqual(XCTWaiter.wait(for: [count], timeout: 5), .completed)
        XCTAssertEqual(
            rows(in: app).count, 2, "Explicit Save must add one clip, preserving the image")
    }

    @MainActor
    private func launchOCR(language: String, appearance: String) -> XCUIApplication {
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item", "-use-temp-durable-store",
            "-seed-manual-ocr", "-force-free-tier", "-start-capture-paused",
            "-ui-test-paste-sink", "copiedOnly", "-AppleLanguages", "(\(language))",
            "-appearance", appearance
        ]
        app.launch()
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        return app
    }

    @MainActor
    private func rows(in app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "clip-row")
    }

    @MainActor
    private func openReview(in app: XCUIApplication) throws -> XCUIElement {
        let row = rows(in: app).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        try SynthesizedInput.requireForeground(app)
        row.rightClick()
        let extract = app.menuItems["image-copy-text"].firstMatch
        XCTAssertTrue(extract.waitForExistence(timeout: 3))
        extract.click()
        let review = app.buttons["ocr-review"].firstMatch
        XCTAssertTrue(review.waitForExistence(timeout: 15))
        review.click()
        let text = app.textViews["ocr-review-text"].firstMatch
        XCTAssertTrue(text.waitForExistence(timeout: 5))
        return text
    }

    @MainActor
    private func attach(_ window: XCUIElement, named name: String) {
        let attachment = XCTAttachment(screenshot: window.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

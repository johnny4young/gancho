import XCTest

/// Manual OCR from the history panel renders IN the peek: the recognized text
/// appears beside the image with one region per line on the thumbnail, the
/// copy is automatic only when the clipboard stayed untouched, edits stay
/// transient until Save, and Paste keeps position 0 of the action list.
final class ManualOCRUITests: XCTestCase {
    @MainActor
    func testRecognizedTextAppearsInThePeekWithoutCreatingAClip() throws {
        let app = launchOCR(language: "en", appearance: "dark")
        defer { app.terminate() }
        try recognizeSeededImage(in: app)
        let firstLine = element("peek-ocr-line-0", in: app)
        XCTAssertTrue(firstLine.waitForExistence(timeout: 15), "the section never rendered a line")
        XCTAssertTrue(
            firstLine.label.contains("Hola"), "first recognized line was \(firstLine.label)")
        let secondLine = app.descendants(matching: .any).matching(
            NSPredicate(
                format: "identifier BEGINSWITH 'peek-ocr-line-' AND label CONTAINS 'imagen'")
        ).firstMatch
        XCTAssertTrue(secondLine.waitForExistence(timeout: 5), "the second line is missing")
        // The seed leaves the clipboard untouched, so the text was copied
        // automatically and the section says so — no toast, no window.
        let status = element("peek-ocr-status", in: app)
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(status.label, "Copied to clipboard")
        XCTAssertTrue(
            element("peek-ocr-region-1", in: app).exists,
            "every recognized line gets a region over the thumbnail")
        XCTAssertFalse(app.buttons["ocr-review"].exists, "the peek surface must not toast")
        XCTAssertEqual(rows(in: app).count, 1, "Recognizing must not create another history clip")
        // The fixture's third line is a link, so exactly one link chip appears,
        // named by its host. Clicking it never leaves the app under the paste
        // sink, and the section stays put.
        let link = app.buttons["peek-ocr-link-0"].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 5), "the link chip never appeared")
        XCTAssertEqual(link.label, "Open gancho.app")
        XCTAssertEqual(
            app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'peek-ocr-link-'"))
                .count,
            1, "one link in the image, one chip")
        link.click()
        XCTAssertTrue(firstLine.exists, "opening a link must not dismiss the section")
        attachPanel(app, named: "Manual OCR — English dark peek")
    }

    @MainActor
    func testSpanishEditKeepsTheDraftTransientUntilSave() throws {
        let app = launchOCR(language: "es", appearance: "light")
        defer { app.terminate() }
        try recognizeSeededImage(in: app)
        let edit = app.buttons["peek-ocr-edit"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 15))
        XCTAssertEqual(edit.label, "Editar")
        XCTAssertEqual(app.buttons["peek-ocr-copy"].firstMatch.label, "Copiar todo")
        edit.click()
        let editor = app.textViews["peek-ocr-editor"].firstMatch
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        try typeTextReliably("Texto editado: canción y café", into: editor, in: app)
        attachPanel(app, named: "Manual OCR — Spanish light inline editor")
        app.buttons["peek-ocr-editor-cancel"].click()
        XCTAssertTrue(editor.waitForNonExistence(timeout: 5))
        XCTAssertEqual(rows(in: app).count, 1, "Cancelling an edit must not save a clip")
        app.buttons["peek-ocr-edit"].firstMatch.click()
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        try typeTextReliably("Texto editado: canción y café", into: editor, in: app)
        app.buttons["peek-ocr-editor-save"].click()
        let count = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count == 2"), object: rows(in: app))
        XCTAssertEqual(
            XCTWaiter.wait(for: [count], timeout: 5), .completed,
            "Explicit Save must add one clip, preserving the image")
    }

    /// Position 0 of the peek action list is what Return runs (`actionIndex`
    /// resets to 0 on focus), so offering OCR must not displace Paste as the
    /// default keyboard action on an image clip. Asserted by geometry: the
    /// dock lays its actions out left to right in list order.
    @MainActor
    func testPasteStaysTheFirstPeekActionForImageClips() throws {
        let app = launchOCR(language: "en", appearance: "dark")
        defer { app.terminate() }
        XCTAssertTrue(rows(in: app).firstMatch.waitForExistence(timeout: 15))
        let paste = element("preview-paste", in: app)
        let ocr = element("image-copy-text", in: app)
        XCTAssertTrue(paste.waitForExistence(timeout: 10), "the peek must offer Paste")
        XCTAssertTrue(ocr.waitForExistence(timeout: 10), "the peek must offer OCR on an image")
        XCTAssertEqual(paste.frame.minY, ocr.frame.minY, accuracy: 1, "both live in the dock")
        XCTAssertLessThan(
            paste.frame.minX, ocr.frame.minX,
            "Paste must stay the first peek action: position 0 is what Return runs")
    }

    @MainActor
    private func launchOCR(language: String, appearance: String) -> XCUIApplication {
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item", "-use-temp-durable-store",
            "-place-panel-for-ui-test", "-opaque-panel-for-ui-test",
            "-seed-manual-ocr", "-force-free-tier", "-start-capture-paused",
            "-ui-test-paste-sink", "copy-only", "-AppleLanguages", "(\(language))",
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
    private func element(_ identifier: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Right-click the seeded image row and ask for its text. The row is the
    /// selected clip, so the request lands in the peek.
    @MainActor
    private func recognizeSeededImage(in app: XCUIApplication) throws {
        let row = rows(in: app).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15))
        try SynthesizedInput.requireForeground(app)
        row.rightClick()
        let extract = app.menuItems["image-copy-text"].firstMatch
        XCTAssertTrue(extract.waitForExistence(timeout: 3))
        extract.click()
    }

    /// The panel is a floating NSPanel on the ACTIVE display, so a screen
    /// capture could show an unrelated desktop; capture the panel element only.
    @MainActor
    private func attachPanel(_ app: XCUIApplication, named name: String) {
        guard
            let panel = app.children(matching: .any).allElementsBoundByIndex.first(where: {
                $0.exists && $0.frame.width > 200 && $0.frame.height > 200
            })
        else { return }
        let attachment = XCTAttachment(screenshot: panel.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

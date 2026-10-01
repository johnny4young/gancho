import XCTest

final class TextRecipeUITests: XCTestCase {
    @MainActor func testEnglishLight() throws { try verify("en", "light") }
    @MainActor func testEnglishDark() throws { try verify("en", "dark") }
    @MainActor func testSpanishLight() throws { try verify("es", "light") }
    @MainActor func testSpanishDark() throws { try verify("es", "dark") }
    @MainActor private func verify(_ language: String, _ appearance: String) throws {
        continueAfterFailure = false
        let app = launch(language, appearance)
        defer { app.terminate() }
        try openReview(app)
        let run = app.buttons["text-recipe-run"].firstMatch
        XCTAssertTrue(run.waitForHittable(timeout: 5))
        XCTAssertTrue(run.isEnabled)
        run.click()
        let copy = app.buttons["text-recipe-copy"].firstMatch
        XCTAssertTrue(copy.waitForHittable(timeout: 5))
        let enabled = NSPredicate(format: "enabled == true")
        expectation(for: enabled, evaluatedWith: copy)
        waitForExpectations(timeout: 5)
        let attachment = XCTAttachment(
            screenshot: app.sheets.firstMatch.screenshot())
        attachment.name = "Recipe review — synthetic — \(language) — \(appearance)"
        attachment.lifetime = .keepAlways
        add(attachment)
        app.buttons["text-recipe-cancel"].firstMatch.click()
        XCTAssertTrue(run.waitForNonExistence(timeout: 5))
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "clip-row").firstMatch.exists)
    }
    @MainActor private func launch(
        _ language: String, _ appearance: String
    ) -> GanchoUITestApplication {
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item", "-use-temp-durable-store",
            "-seed-clip-editing", "-force-free-tier", "-start-capture-paused",
            "-ui-test-paste-sink", "copy-only",
            "-ui-test-defaults-suite", "com.johnny4young.gancho.uitests.recipes.\(UUID())",
            "-opaque-panel-for-ui-test", "-panel-position", "centered", "-AppleLanguages",
            "(\(language))",
            "-appearance", appearance, "-panel-content-width", "720", "-panel-content-height",
            "460",
            "-panel-text-size", "large"
        ]
        app.launch()
        app.activate()
        return app
    }
    @MainActor
    private func openReview(_ app: GanchoUITestApplication) throws {
        try SynthesizedInput.requireForeground(app)
        let row = app.descendants(matching: .any).matching(identifier: "clip-row").firstMatch
        XCTAssertTrue(row.waitForHittable(timeout: 10))
        row.click()
        let transform = app.descendants(matching: .any)["transform-menu"].firstMatch
        XCTAssertTrue(transform.waitForHittable(timeout: 5))
        transform.click()
        let recipes = app.menuItems["text-recipes-action"].firstMatch
        XCTAssertTrue(recipes.waitForExistence(timeout: 5))
        recipes.hover()
        try SynthesizedInput.requireForeground(app)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(app.buttons["text-recipe-new"].firstMatch.waitForHittable(timeout: 5))
    }

    @MainActor
    func testTransformedPreviewAndExplicitCopyPreserveOriginal() throws {
        continueAfterFailure = false
        let app = launch("en", "light")
        defer { app.terminate() }
        let rows = app.descendants(matching: .any).matching(identifier: "clip-row")
        XCTAssertTrue(rows.firstMatch.waitForHittable(timeout: 10))
        let originalCount = rows.count
        try openReview(app)
        let original = "Yesterday: fixed search\nToday: improve editing\nBlockers: none"
        XCTAssertTrue(app.staticTexts[original].firstMatch.exists)
        app.descendants(matching: .any)["text-recipe-action-picker"].firstMatch.click()
        let uppercase = app.menuItems["UPPERCASE"].firstMatch
        XCTAssertTrue(uppercase.waitForExistence(timeout: 5))
        uppercase.click()
        app.buttons["text-recipe-add-step"].firstMatch.click()
        app.buttons["text-recipe-run"].firstMatch.click()
        XCTAssertTrue(
            app.staticTexts[original.uppercased()].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts[original].firstMatch.exists)
        let copy = app.buttons["text-recipe-copy"].firstMatch
        XCTAssertTrue(copy.isEnabled)
        let attachment = XCTAttachment(screenshot: app.sheets.firstMatch.screenshot())
        attachment.name = "Recipe transformation before explicit copy — synthetic"
        attachment.lifetime = .keepAlways
        add(attachment)
        copy.click()
        XCTAssertTrue(copy.waitForNonExistence(timeout: 5))
        XCTAssertEqual(rows.count, originalCount)
        try openReview(app)
        XCTAssertTrue(app.staticTexts[original].firstMatch.waitForExistence(timeout: 5))
        app.buttons["text-recipe-cancel"].firstMatch.click()
    }

    @MainActor
    func testCreateReorderRenameReopenAndDeleteKeepsOriginalClip() throws {
        continueAfterFailure = false
        let app = launch("en", "light")
        defer { app.terminate() }
        try openReview(app)
        app.buttons["text-recipe-new"].firstMatch.click()
        let name = app.textFields["text-recipe-name"].firstMatch
        try typeTextReliably("Synthetic review recipe", into: name, in: app)
        app.buttons["text-recipe-add-step"].firstMatch.click()
        let up = app.buttons.matching(identifier: "text-recipe-move-up-button").element(boundBy: 1)
        XCTAssertTrue(up.isEnabled)
        up.click()
        let save = app.buttons["text-recipe-save"].firstMatch
        XCTAssertTrue(save.isEnabled)
        save.click()
        expectation(for: NSPredicate(format: "enabled == false"), evaluatedWith: save)
        waitForExpectations(timeout: 5)
        try typeTextReliably("Renamed synthetic recipe", into: name, in: app)
        save.click()
        expectation(for: NSPredicate(format: "enabled == false"), evaluatedWith: save)
        waitForExpectations(timeout: 5)
        app.buttons["text-recipe-cancel"].firstMatch.click()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5))
        try openReview(app)
        let picker = app.descendants(matching: .any)["text-recipe-picker"].firstMatch
        picker.click()
        let saved = app.menuItems["Renamed synthetic recipe"].firstMatch
        XCTAssertTrue(saved.waitForExistence(timeout: 5))
        saved.hover()
        try SynthesizedInput.requireForeground(app)
        app.typeKey(.return, modifierFlags: [])
        expectation(
            for: NSPredicate(format: "value == %@", "Renamed synthetic recipe"),
            evaluatedWith: name)
        waitForExpectations(timeout: 5)
        XCTAssertEqual(app.buttons.matching(identifier: "text-recipe-remove-step-button").count, 2)
        app.buttons["text-recipe-delete"].firstMatch.click()
        XCTAssertTrue(name.waitForNonExistence(timeout: 5))
        app.buttons["text-recipe-cancel"].firstMatch.click()
        XCTAssertTrue(
            app.descendants(matching: .any).matching(identifier: "clip-row").firstMatch.exists)
    }

}

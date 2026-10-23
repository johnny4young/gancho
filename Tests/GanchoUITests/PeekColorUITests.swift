import XCTest

/// The colour clip's hero (formats, contrast, Convert) and the image clip's
/// eyedropper and dominant colours, over the synthetic visual library.
final class PeekColorUITests: XCTestCase {
    @MainActor
    private func launch() -> XCUIApplication {
        continueAfterFailure = false
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item", "-use-temp-durable-store",
            "-seed-visual-library", "-force-free-tier", "-start-capture-paused",
            "-suppress-paused-notice-for-ui-test", "-opaque-panel-for-ui-test",
            "-place-panel-for-ui-test", "-suppress-storage-notice-for-ui-test",
            "-ui-test-paste-sink", "pasted", "-AppleLanguages", "(en)",
            "-ui-test-defaults-suite", "com.johnny4young.gancho.uitests.color.\(UUID().uuidString)"
        ]
        app.launch()
        app.activate()
        return app
    }

    @MainActor
    private func rows(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any).matching(identifier: "clip-row")
    }

    @MainActor
    private func select(_ label: String, in app: XCUIApplication) -> XCUIElement {
        let row = rows(app).matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
        XCTAssertTrue(
            row.waitForExistence(timeout: 15),
            "\(label) in \(rows(app).allElementsBoundByIndex.map(\.label))")
        row.click()
        return row
    }

    /// macOS static text reports its string as the value.
    @MainActor
    private func text(of element: XCUIElement) -> String {
        element.label.isEmpty ? element.value as? String ?? "" : element.label
    }

    @MainActor
    func testColorHeroShowsFormatsContrastAndConvert() throws {
        let app = launch()
        defer { app.terminate() }
        _ = select("color, #008080", in: app)
        // The colour hero is the peek hero's only child, so SwiftUI folds its
        // container into `peek-hero`; its rows are looked up there.
        let hero = app.descendants(matching: .any)["peek-hero"].firstMatch
        XCTAssertTrue(
            hero.descendants(matching: .any)["peek-color-format-hex"].firstMatch
                .waitForExistence(timeout: 5))
        for (key, value) in [
            ("hex", "#008080"), ("rgb", "rgb(0, 128, 128)"), ("hsl", "hsl(180, 100%, 25%)"),
            ("swift", "Color(red: 0, green: 0.502, blue: 0.502)")
        ] {
            let row = hero.descendants(matching: .any)["peek-color-format-\(key)"].firstMatch
            XCTAssertTrue(row.exists, key)
            let shown = row.staticTexts.allElementsBoundByIndex.map(text(of:))
            XCTAssertTrue(shown.contains(value), "\(key): \(shown)")
        }
        let hexTexts = hero.staticTexts.allElementsBoundByIndex.map(text(of:)).filter {
            $0 == "#008080"
        }
        XCTAssertEqual(hexTexts.count, 1, "the hero replaces the plain text body")
        let light = hero.descendants(matching: .any)["peek-color-contrast-light"].firstMatch
        let dark = hero.descendants(matching: .any)["peek-color-contrast-dark"].firstMatch
        let lightTexts = light.staticTexts.allElementsBoundByIndex.map(text(of:))
        let darkTexts = dark.staticTexts.allElementsBoundByIndex.map(text(of:))
        XCTAssertTrue(lightTexts.contains("4.7 : 1") && lightTexts.contains("AA"), "\(lightTexts)")
        XCTAssertTrue(
            darkTexts.contains("3.5 : 1") && darkTexts.contains("AA Large"), "\(darkTexts)")

        hero.buttons["peek-color-copy-hex"].firstMatch.click()
        let toast = app.descendants(matching: .any)["gancho-toast"].firstMatch
        XCTAssertTrue(toast.waitForExistence(timeout: 5), "copying a format confirms it")

        let convert = app.buttons["preview-convert"].firstMatch
        XCTAssertTrue(convert.exists, "Convert sits in the colour dock")
        XCTAssertFalse(
            app.buttons["peek-more-actions"].firstMatch.exists,
            "Convert is not repeated behind More actions")
        try SynthesizedInput.requireForeground(app)
        app.typeKey(.rightArrow, modifierFlags: [])
        app.typeKey(.return, modifierFlags: .shift)
        let result = app.descendants(matching: .any)["intelligence-result-text"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5), "⇧⏎ opens Convert's result")
    }

    @MainActor
    func testEyedropperSavesTheClickedPixelAsAColorClip() throws {
        let app = launch()
        defer { app.terminate() }
        _ = select("image, 1200 × 600", in: app)
        let before = rows(app).count
        XCTAssertTrue(
            app.descendants(matching: .any)["peek-region-toggle"].firstMatch.waitForExistence(
                timeout: 5))
        try SynthesizedInput.requireForeground(app)
        app.typeKey(.rightArrow, modifierFlags: [])
        app.typeKey("i", modifierFlags: [])
        let eyedropper = app.descendants(matching: .any)["peek-eyedropper"].firstMatch
        XCTAssertTrue(eyedropper.waitForExistence(timeout: 5), "I takes up the eyedropper")
        // The seed's orange circle sits at the centre of the image.
        eyedropper.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()

        let saved = rows(app).matching(NSPredicate(format: "label BEGINSWITH[c] %@", "color"))
        let deadline = Date().addingTimeInterval(10)
        while rows(app).count <= before, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertEqual(rows(app).count, before + 1, "the click saves one colour clip")
        XCTAssertGreaterThanOrEqual(saved.count, 2, "Ocean plus the picked colour")
        XCTAssertFalse(eyedropper.exists, "the eyedropper is put down after a pick")
    }

    @MainActor
    func testDominantSwatchSavesAColorClip() throws {
        let app = launch()
        defer { app.terminate() }
        _ = select("image, 1200 × 600", in: app)
        let before = rows(app).count
        let swatches = app.descendants(matching: .any)["peek-dominant-colors"].firstMatch
        XCTAssertTrue(swatches.waitForExistence(timeout: 5))
        let first = app.buttons["peek-dominant-color-0"].firstMatch
        XCTAssertTrue(first.exists)
        XCTAssertTrue(app.buttons["peek-dominant-color-1"].firstMatch.exists, "teal and orange")
        first.click()
        let deadline = Date().addingTimeInterval(10)
        while rows(app).count <= before, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertEqual(rows(app).count, before + 1)
    }
}

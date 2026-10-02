import XCTest

final class TranslationCapabilityUITests: XCTestCase {
    @MainActor
    func testInstalledPairOfferedWithoutGenerativeModel() throws {
        try verify(language: "en", extraArguments: [])
    }

    @MainActor func testEnglishLight() throws {
        try verify(language: "en", extraArguments: ["-appearance", "light"])
    }
    @MainActor func testEnglishDarkSmallLargeText() throws {
        try verify(
            language: "en",
            extraArguments: [
                "-appearance", "dark", "-panel-content-width", "720", "-panel-content-height",
                "460", "-panel-text-size", "large"
            ])
    }
    @MainActor func testSpanishLight() throws {
        try verify(language: "es", extraArguments: ["-appearance", "light"])
    }
    @MainActor func testSpanishDarkSmallLargeText() throws {
        try verify(
            language: "es",
            extraArguments: [
                "-appearance", "dark", "-panel-content-width", "720", "-panel-content-height",
                "460", "-panel-text-size", "large"
            ])
    }

    @MainActor
    private func verify(language: String, extraArguments: [String]) throws {
        continueAfterFailure = false
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item", "-use-temp-durable-store",
            "-seed-clip-editing", "-force-free-tier", "-start-capture-paused", "-AppleLanguages",
            "(\(language))",
            "-opaque-panel-for-ui-test", "-place-panel-for-ui-test",
            "-ui-test-defaults-suite", "com.johnny4young.gancho.uitests.translation.\(UUID())",
            "-ui-test-installed-translation", "-ui-test-paste-sink", "copy-only"
        ]
        app.launchArguments += extraArguments
        app.launch()
        defer { app.terminate() }
        app.activate()
        let row = app.descendants(matching: .any).matching(identifier: "clip-row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        try SynthesizedInput.requireForeground(app)
        app.typeKey(.tab, modifierFlags: [])
        row.click()
        let panel = app.dialogs["history-panel"].firstMatch
        XCTAssertTrue(panel.exists)
        let originalFrame = panel.frame
        let menu = app.descendants(matching: .any).matching(identifier: "smart-paste-menu")
            .firstMatch
        XCTAssertTrue(menu.waitForExistence(timeout: 5))
        menu.click()
        let translate = app.descendants(matching: .any).matching(
            identifier: "translation-destinations-menu"
        ).firstMatch
        XCTAssertTrue(translate.waitForExistence(timeout: 5))
        XCTAssertTrue(app.menuItems["smart-paste-redactpii-action"].firstMatch.exists)
        XCTAssertFalse(app.menuItems["smart-paste-summarize-action"].firstMatch.exists)
        app.descendants(matching: .any).matching(identifier: "translation-destinations-menu")
            .firstMatch.hover()
        let spanish = app.menuItems["translation-target-es"].firstMatch
        XCTAssertTrue(spanish.waitForExistence(timeout: 5))
        XCTAssertTrue(spanish.isEnabled)
        try SynthesizedInput.requireForeground(app)
        spanish.click()
        let result = app.descendants(matching: .any).matching(
            identifier: "intelligence-result-text"
        ).firstMatch
        let found = result.waitForExistence(timeout: 5)
        if !found, panel.exists {
            attachPanelScreenshot(panel, name: "Translation result missing — synthetic")
        }
        XCTAssertTrue(found)
        XCTAssertTrue(
            result.label.contains("Traducción sintética")
                || (result.value as? String)?.contains("Traducción sintética") == true)
        XCTAssertEqual(panel.frame.width, originalFrame.width, accuracy: 1)
        XCTAssertEqual(panel.frame.height, originalFrame.height, accuracy: 1)
        attachPanelScreenshot(
            panel,
            name:
                "Installed translation — synthetic — \(language) — \(extraArguments.joined(separator: " "))"
        )
    }

    @MainActor
    private func attachPanelScreenshot(_ panel: XCUIElement, name: String) {
        let attachment = XCTAttachment(screenshot: panel.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

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
            "-ui-test-installed-translation"
        ]
        app.launchArguments += extraArguments
        app.launch()
        defer { app.terminate() }
        app.activate()
        let row = app.descendants(matching: .any).matching(identifier: "clip-row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.click()
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
            .firstMatch.click()
        let spanish = app.menuItems["translation-target-es"].firstMatch
        XCTAssertTrue(spanish.waitForExistence(timeout: 5))
        XCTAssertTrue(spanish.isEnabled)
        spanish.click()
        let result = app.descendants(matching: .any).matching(
            identifier: "intelligence-result-text"
        ).firstMatch
        let found = result.waitForExistence(timeout: 5)
        let panel = app.dialogs["history-panel"].firstMatch
        if !found, panel.exists {
            let failure = XCTAttachment(screenshot: panel.screenshot())
            failure.name = "Translation result missing — synthetic"
            failure.lifetime = .keepAlways
            add(failure)
        }
        XCTAssertTrue(found)
        XCTAssertTrue(
            result.label.contains("Traducción sintética")
                || (result.value as? String)?.contains("Traducción sintética") == true)
        let attachment = XCTAttachment(
            screenshot: app.dialogs["history-panel"].firstMatch.screenshot())
        attachment.name =
            "Installed translation — synthetic — \(language) — \(extraArguments.joined(separator: " "))"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

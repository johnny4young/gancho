import XCTest

final class TextRecipeUITests: XCTestCase {
    @MainActor func testEnglishLight() throws { try verify("en", "light") }
    @MainActor func testEnglishDark() throws { try verify("en", "dark") }
    @MainActor func testSpanishLight() throws { try verify("es", "light") }
    @MainActor func testSpanishDark() throws { try verify("es", "dark") }
    @MainActor private func verify(_ language: String, _ appearance: String) throws {
        continueAfterFailure = false
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item", "-use-temp-durable-store",
            "-seed-clip-editing", "-force-free-tier", "-start-capture-paused",
            "-ui-test-paste-sink", "copy-only",
            "-ui-test-defaults-suite", "com.johnny4young.gancho.uitests.recipes.\(UUID())",
            "-opaque-panel-for-ui-test", "-place-panel-for-ui-test", "-AppleLanguages",
            "(\(language))",
            "-appearance", appearance, "-panel-content-width", "720", "-panel-content-height",
            "460",
            "-panel-text-size", "large"
        ]
        app.launch()
        defer { app.terminate() }
        app.activate()
        let row = app.descendants(matching: .any).matching(identifier: "clip-row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.click()
        let transform = app.descendants(matching: .any)["transform-menu"].firstMatch
        XCTAssertTrue(transform.waitForExistence(timeout: 5))
        transform.click()
        let recipes = app.menuItems["text-recipes-action"].firstMatch
        XCTAssertTrue(recipes.waitForExistence(timeout: 5))
        recipes.click()
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
        XCTAssertTrue(row.exists)
    }
}

import XCTest

/// A secret's peek: the stored mask with its countdown, a reveal that masks
/// itself again, and Delete now.
final class PeekSecretUITests: XCTestCase {
    @MainActor
    func testSecretPeekCountsDownRevealsForTenSecondsAndDeletes() throws {
        let nonce = UUID().uuidString
        let app = launchPanel(nonce: nonce)
        defer { app.terminate() }
        let secrets = app.buttons["filter-secrets"].firstMatch
        XCTAssertTrue(secrets.waitForExistence(timeout: 15))
        secrets.click()
        let row = app.descendants(matching: .any).matching(identifier: "clip-row")
            .matching(NSPredicate(format: "label BEGINSWITH 'secret,'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.click()

        let hero = app.descendants(matching: .any)["peek-secret-hero"].firstMatch
        XCTAssertTrue(hero.waitForExistence(timeout: 5))
        XCTAssertEqual(text(of: app.staticTexts["peek-masked"].firstMatch), "●●●● 4Q2v")
        XCTAssertEqual(text(of: app.staticTexts["preview-title"].firstMatch), "Secret")
        let countdown = app.descendants(matching: .any)["peek-secret-countdown"].firstMatch
        XCTAssertTrue(text(of: countdown).hasPrefix("Self-destructs in 9:"), text(of: countdown))
        XCTAssertTrue(app.descendants(matching: .any)["peek-secret-lifetime"].firstMatch.exists)
        XCTAssertFalse(
            app.descendants(matching: .any)["peek-expiry"].firstMatch.exists,
            "the hero's countdown replaces the header's expiry chip")
        try keepRender(of: "history-panel", in: app, named: "Secret peek — masked with countdown")

        app.buttons["peek-reveal-button"].firstMatch.click()
        let revealed = app.staticTexts["peek-revealed"].firstMatch
        XCTAssertTrue(revealed.waitForExistence(timeout: 5))
        XCTAssertEqual(text(of: revealed), "synthetic-peek-secret-4Q2v")
        XCTAssertTrue(
            app.staticTexts["peek-masked"].firstMatch.waitForExistence(timeout: 13),
            "the reveal masks itself again after 10 s")
        XCTAssertFalse(revealed.exists)

        // Private mode while revealed masks it at once, and it stays masked after.
        app.buttons["peek-reveal-button"].firstMatch.click()
        XCTAssertTrue(revealed.waitForExistence(timeout: 5))
        GanchoUITestCommands.post("togglePrivateMode", token: nonce)
        XCTAssertTrue(
            app.descendants(matching: .any)["peek-private-mode"].firstMatch
                .waitForExistence(timeout: 5))
        GanchoUITestCommands.post("togglePrivateMode", token: nonce)
        XCTAssertTrue(app.staticTexts["peek-masked"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertFalse(revealed.exists)

        app.buttons["peek-delete-now"].firstMatch.click()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5), "Delete now removes the secret")
    }

    /// macOS puts a static text's string in its label or its value.
    private func text(of element: XCUIElement) -> String {
        element.label.isEmpty ? (element.value as? String ?? "") : element.label
    }

    @MainActor
    private func launchPanel(nonce: String) -> XCUIApplication {
        continueAfterFailure = false
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item", "-use-temp-durable-store",
            "-seed-peek-secret", "-force-free-tier", "-start-capture-paused",
            "-command-nonce", nonce,
            "-opaque-panel-for-ui-test", "-place-panel-for-ui-test",
            "-suppress-storage-notice-for-ui-test", "-AppleLanguages", "(en)",
            "-panel-content-width", "720", "-panel-content-height", "460",
            "-ui-test-defaults-suite",
            "com.johnny4young.gancho.uitests.secret.\(UUID().uuidString)"
        ]
        app.launch()
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        return app
    }
}

import XCTest

/// The v4 panel's provenance header, scope counts and first-run lesson, over
/// synthetic clips or an empty throwaway store.
final class PanelProvenanceUITests: XCTestCase {
    private static let seededClips = 5

    @MainActor
    private func launch(seeded: Bool) -> XCUIApplication {
        let app = GanchoUITestApplication()
        app.launchArguments =
            [
                "-open-panel-on-launch", "-use-in-process-status-item", "-use-temp-durable-store",
                "-force-free-tier", "-start-capture-paused", "-suppress-paused-notice-for-ui-test",
                "-opaque-panel-for-ui-test", "-place-panel-for-ui-test",
                "-suppress-storage-notice-for-ui-test", "-AppleLanguages", "(en)",
                "-ui-test-defaults-suite",
                "com.johnny4young.gancho.uitests.provenance.\(UUID().uuidString)"
            ] + (seeded ? ["-seed-visual-library", "-seed-peek-link"] : [])
        app.launch()
        return app
    }

    @MainActor
    private func row(_ label: String, in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "clip-row")
            .matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
    }

    @MainActor
    func testPeekHeaderCarriesProvenanceAndTheTitleSitsBelow() throws {
        let app = launch(seeded: true)
        defer { app.terminate() }
        let link = row("example.com", in: app)
        XCTAssertTrue(link.waitForExistence(timeout: 15))
        link.click()

        let header = app.descendants(matching: .any)["peek-provenance"].firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        XCTAssertTrue(header.descendants(matching: .any)["peek-age"].firstMatch.exists)
        // Sync is off in UI tests, so the chip says nothing rather than guess.
        XCTAssertFalse(header.descendants(matching: .any)["peek-sync-state"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["preview-title"].firstMatch.exists)
        let decoded = app.descendants(matching: .any)["peek-link-decoded"].firstMatch
        XCTAssertTrue(decoded.exists)
        XCTAssertTrue(decoded.label.contains("/a/b?q=a&b"), decoded.label)
    }

    @MainActor
    func testMaskedClipHidesProvenance() throws {
        let app = launch(seeded: true)
        defer { app.terminate() }
        let masked = row("•••", in: app)
        XCTAssertTrue(masked.waitForExistence(timeout: 15))
        masked.click()
        let header = app.descendants(matching: .any)["peek-provenance"].firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 5))
        XCTAssertFalse(header.descendants(matching: .any)["peek-age"].firstMatch.exists)
        XCTAssertFalse(header.descendants(matching: .any)["peek-source-app"].firstMatch.exists)
    }

    @MainActor
    func testActiveScopeChipShowsTheBoardTotal() throws {
        let app = launch(seeded: true)
        defer { app.terminate() }
        let all = app.buttons["board-all"].firstMatch
        XCTAssertTrue(all.waitForExistence(timeout: 15))
        let counted = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "All clips · \(Self.seededClips)"),
            object: all)
        XCTAssertEqual(XCTWaiter.wait(for: [counted], timeout: 10), .completed, all.label)
    }

    @MainActor
    func testEmptyPanelTeachesThreeKeysAndOffersTheImporter() throws {
        let app = launch(seeded: false)
        defer { app.terminate() }
        let stage = app.descendants(matching: .any)["panel-first-run-stage"].firstMatch
        XCTAssertTrue(stage.waitForExistence(timeout: 15))
        let importer = app.buttons["panel-empty-import-button"].firstMatch
        XCTAssertTrue(importer.exists)
        importer.click()
        XCTAssertTrue(
            app.descendants(matching: .any)["migration-import-sheet"].firstMatch
                .waitForExistence(timeout: 5))
    }
}

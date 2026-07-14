import XCTest

final class ReuseSuggestionUITests: XCTestCase {
    @MainActor
    func testThirdCopyOffersOneTapSnippetPromotionAndCapturesEvidence() throws {
        let app = try launchSeededApp()
        defer { app.terminate() }

        try copySeededClip(in: app)

        let banner = app.descendants(matching: .any)["reuse-suggestion"].firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Used 3 times — save as a snippet?"].exists)

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "iOS exact-third-use snippet suggestion"
        attachment.lifetime = .keepAlways
        add(attachment)

        let action = app.buttons["reuse-suggestion-action"].firstMatch
        XCTAssertTrue(action.isHittable)
        action.tap()

        XCTAssertTrue(app.staticTexts["Saved as snippet"].waitForExistence(timeout: 5))
    }

    @MainActor
    func testDismissedThresholdSuggestionDoesNotRepeat() throws {
        let app = try launchSeededApp()
        defer { app.terminate() }

        try copySeededClip(in: app)
        let banner = app.descendants(matching: .any)["reuse-suggestion"].firstMatch
        XCTAssertTrue(banner.waitForExistence(timeout: 8))
        app.buttons["reuse-suggestion-dismiss"].firstMatch.tap()
        waitForDisappearance(of: banner, timeout: 2)

        try copySeededClip(in: app)
        let noRepeat = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true"), object: banner)
        noRepeat.isInverted = true
        XCTAssertEqual(
            XCTWaiter.wait(for: [noRepeat], timeout: 2), .completed,
            "use four must not repeat the exact-third-use suggestion")
    }

    @MainActor
    private func launchSeededApp() throws -> XCUIApplication {
        let app = XCUIApplication()
        // Xcode's Simulator runner can occasionally launch without the requested
        // process arguments. Retry once rather than exercising production-style
        // storage or onboarding state with a missing synthetic fixture.
        for _ in 0..<2 {
            app.terminate()
            app.launchArguments = [
                "-skip-welcome-on-launch", "-use-temp-durable-store", "-seed-reuse-suggestion",
                "-force-free-tier", "-AppleLanguages", "(en)"
            ]
            app.launch()
            let row = app.descendants(matching: .any).matching(identifier: "clip-row").firstMatch
            if row.waitForExistence(timeout: 8) { return app }
        }
        return try XCTUnwrap(
            nil as XCUIApplication?,
            "the isolated reuse-suggestion fixture did not become available after one retry")
    }

    @MainActor
    private func copySeededClip(in app: XCUIApplication) throws {
        let capture = app.descendants(matching: .any)["capture-screen"].firstMatch
        guard capture.waitForExistence(timeout: 10) else {
            throw XCTSkip("capture screen is not reachable on this runner")
        }
        let row = app.descendants(matching: .any).matching(identifier: "clip-row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8))
        row.tap()
        let copy = app.buttons["Copy"].firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        XCTAssertTrue(copy.isHittable)
        copy.tap()
    }

    @MainActor
    private func waitForDisappearance(of element: XCUIElement, timeout: TimeInterval) {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: timeout), .completed)
    }
}

import XCTest

/// The Library's Suggested group: clips used often enough to offer keeping,
/// each with Keep, Never and Dismiss.
final class SuggestedSnippetsUITests: XCTestCase {
    @MainActor
    private func openLibrary(
        appearance: String = "light", extra: [String] = []
    ) throws -> (XCUIApplication, XCUIElement) {
        continueAfterFailure = false
        let token = UUID().uuidString
        let app = GanchoUITestApplication()
        app.launchArguments =
            extra + [
                "-open-panel-on-launch", "-use-in-process-status-item", "-use-temp-durable-store",
                "-seed-snippet-suggestions", "-force-free-tier", "-start-capture-paused",
                "-suppress-storage-notice-for-ui-test", "-place-panel-for-ui-test",
                "-opaque-panel-for-ui-test", "-place-library-for-ui-test", "-AppleLanguages",
                "(en)", "-appearance", appearance, "-telemetry-consent", "disabled",
                "-command-nonce", token, "-ui-test-defaults-suite",
                "com.johnny4young.gancho.uitests.suggested.\(UUID().uuidString)"
            ]
        app.launch()
        XCTAssertTrue(app.textFields["search-field"].firstMatch.appears(within: 15))
        GanchoUITestCommands.post("library", token: token)
        let library = app.windows["Library"].firstMatch
        XCTAssertTrue(library.appears(within: 5))
        return (app, library)
    }

    @MainActor
    private func buttons(_ answer: String, in library: XCUIElement) -> XCUIElementQuery {
        library.descendants(matching: .any).matching(identifier: "snippet-suggestion-\(answer)")
    }

    @MainActor
    private func waitForCount(_ count: Int, of query: XCUIElementQuery) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count == %d", count), object: query)
        return XCTWaiter().wait(for: [expectation], timeout: 8) == .completed
    }

    @MainActor
    func testGroupListsEarnedClipsMostUsedFirstAndNeverASecret() throws {
        let (app, library) = try openLibrary()
        defer { app.terminate() }
        XCTAssertTrue(waitForCount(2, of: buttons("keep", in: library)))
        XCTAssertTrue(library.staticTexts["Used 5 times"].exists)
        XCTAssertTrue(library.staticTexts["Used 3 times"].exists)
        XCTAssertFalse(library.staticTexts["Used 2 times"].exists)
        XCTAssertFalse(library.staticTexts["Used 9 times"].exists, "never a secret")
        let first = library.staticTexts["Used 5 times"].frame.minY
        XCTAssertLessThan(first, library.staticTexts["Used 3 times"].frame.minY)
        try keepRender(of: "Library", in: app, named: "Library suggested snippets")
    }

    @MainActor
    func testKeepMakesItASnippet() throws {
        let (app, library) = try openLibrary()
        defer { app.terminate() }
        let keep = buttons("keep", in: library)
        XCTAssertTrue(waitForCount(2, of: keep))
        try SynthesizedInput.requireForeground(app)

        keep.firstMatch.click()
        XCTAssertTrue(waitForCount(1, of: keep))
        XCTAssertFalse(library.staticTexts["No snippets yet"].exists)
    }

    @MainActor
    func testNeverAndDismissTakeItOutOfTheGroup() throws {
        let (app, library) = try openLibrary()
        defer { app.terminate() }
        XCTAssertTrue(waitForCount(2, of: buttons("keep", in: library)))
        try SynthesizedInput.requireForeground(app)

        buttons("never", in: library).firstMatch.click()
        XCTAssertTrue(waitForCount(1, of: buttons("keep", in: library)))
        buttons("dismiss", in: library).firstMatch.click()
        XCTAssertTrue(waitForCount(0, of: buttons("keep", in: library)))
        XCTAssertFalse(
            library.descendants(matching: .any)["snippet-suggestions-header"].exists,
            "an empty group disappears")
    }

    /// The cards quote the clip, so the group hides while the screen is shared.
    @MainActor
    func testScreenShareHidesTheGroup() throws {
        let (app, library) = try openLibrary(extra: ["-simulate-screen-share", "Zoom"])
        defer { app.terminate() }
        // The sidebar has loaded, and the share is picked up on the next 3 s poll.
        XCTAssertTrue(library.staticTexts["No snippets yet"].appears(within: 8))
        RunLoop.current.run(until: Date().addingTimeInterval(4))
        XCTAssertEqual(buttons("keep", in: library).count, 0)
    }
}

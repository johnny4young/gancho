import XCTest

/// The Library's search, kind chips, sort, layout, hover actions and sidebar
/// meters, over a synthetic six-clip store (pinned code, colour, link on a
/// board, image, protected image, secret).
final class LibraryBrowseUITests: XCTestCase {
    private var suite = ""

    override func setUp() {
        continueAfterFailure = false
        suite = "com.johnny4young.gancho.uitests.library-browse.\(UUID().uuidString)"
    }

    @MainActor
    private func openLibrary(
        extra: [String] = [], cards expected: Int = 6
    ) throws -> (XCUIApplication, XCUIElement) {
        let nonce = UUID().uuidString
        let app = GanchoUITestApplication()
        app.launchArguments =
            [
                "-open-panel-on-launch", "-use-in-process-status-item", "-use-temp-durable-store",
                "-seed-visual-library", "-seed-visual-library-extras", "-force-free-tier",
                "-start-capture-paused", "-place-library-for-ui-test",
                "-library-board-size-for-ui-test", "-place-panel-for-ui-test",
                "-suppress-storage-notice-for-ui-test", "-ui-test-paste-sink", "copiedOnly",
                "-AppleLanguages", "(en)", "-ui-test-defaults-suite", suite, "-command-nonce", nonce
            ] + extra
        app.launch()
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        XCTAssertTrue(app.textFields["search-field"].firstMatch.waitForExistence(timeout: 15))
        try SynthesizedInput.requireForeground(app)
        GanchoUITestCommands.post("library", token: nonce)
        let library = app.windows["Library"].firstMatch
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        waitForCards(expected, in: library)
        return (app, library)
    }

    @MainActor
    private func cards(_ library: XCUIElement) -> XCUIElementQuery {
        library.buttons.matching(identifier: "library-clip")
    }

    @MainActor
    private func waitForCards(
        _ count: Int, in library: XCUIElement, file: StaticString = #filePath, line: UInt = #line
    ) {
        let settled = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count == %d", count), object: cards(library))
        XCTAssertEqual(
            XCTWaiter.wait(for: [settled], timeout: 8), .completed,
            "expected \(count) cards, saw \(cards(library).count)", file: file, line: line)
    }

    @MainActor
    func testSearchAndKindChipsNarrowTheCardsAndTheCount() throws {
        let (app, library) = try openLibrary()
        defer { app.terminate() }
        let count = library.staticTexts["library-scope-count"].firstMatch
        XCTAssertEqual(count.value as? String, "6 clips")

        let field = library.textFields["library-search-field"].firstMatch
        app.typeKey("f", modifierFlags: .command)
        try typeTextReliably("gancho", into: field, in: app)
        waitForCards(1, in: library)
        XCTAssertTrue(cards(library).firstMatch.label.hasPrefix("gancho repo"))
        library.buttons["library-search-clear"].firstMatch.click()
        waitForCards(6, in: library)

        library.buttons["library-kind-colors"].firstMatch.click()
        waitForCards(1, in: library)
        XCTAssertTrue(cards(library).firstMatch.label.hasPrefix("Ocean"))
        XCTAssertEqual(count.value as? String, "1 clip")
        library.buttons["library-kind-all"].firstMatch.click()
        waitForCards(6, in: library)
    }

    /// Pinned stays first; inside a date group Oldest reverses capture order.
    @MainActor
    func testOldestReversesTheDateGroups() throws {
        let (app, library) = try openLibrary()
        defer { app.terminate() }
        XCTAssertTrue(cards(library).element(boundBy: 0).label.hasPrefix("Example"))
        XCTAssertTrue(cards(library).element(boundBy: 1).label.hasPrefix("Ocean"))
        library.popUpButtons["library-sort"].firstMatch.click()
        app.menuItems["Oldest"].firstMatch.click()
        let reversed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label BEGINSWITH %@", "Secret"),
            object: cards(library).element(boundBy: 1))
        XCTAssertEqual(XCTWaiter.wait(for: [reversed], timeout: 5), .completed)
        XCTAssertTrue(cards(library).element(boundBy: 0).label.hasPrefix("Example"))
    }

    /// Hover offers Copy, Pin and Board; a protected clip offers no Copy.
    @MainActor
    func testHoverActionsCopyAndSkipCopyOnASecret() throws {
        let (app, library) = try openLibrary()
        defer { app.terminate() }
        let link = cards(library).matching(
            NSPredicate(format: "label BEGINSWITH %@", "gancho repo")
        )
        .firstMatch
        link.hover()
        let copy = library.buttons["library-card-copy"].firstMatch
        XCTAssertTrue(copy.waitForExistence(timeout: 3))
        XCTAssertTrue(library.buttons["library-card-pin"].firstMatch.exists)
        XCTAssertTrue(library.descendants(matching: .any)["library-card-board"].firstMatch.exists)
        copy.click()
        XCTAssertTrue(app.staticTexts["Copied"].firstMatch.waitForExistence(timeout: 3))

        let secret = cards(library).matching(NSPredicate(format: "label BEGINSWITH %@", "Secret"))
            .firstMatch
        secret.hover()
        XCTAssertTrue(library.buttons["library-card-pin"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(library.buttons["library-card-copy"].firstMatch.exists)
        XCTAssertFalse(secret.label.contains("synthetic-secret"), "the card shows the mask only")
    }

    /// A deleted card leaves the header count at once, while its Undo is pending.
    @MainActor
    func testDeletingACardDropsTheCount() throws {
        let (app, library) = try openLibrary()
        defer { app.terminate() }
        let count = library.staticTexts["library-scope-count"].firstMatch
        XCTAssertEqual(count.value as? String, "6 clips")
        let ocean = cards(library).matching(NSPredicate(format: "label BEGINSWITH %@", "Ocean"))
            .firstMatch
        ocean.rightClick()
        app.menuItems["library-delete-action"].firstMatch.click()
        waitForCards(5, in: library)
        let dropped = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", "5 clips"), object: count)
        XCTAssertEqual(XCTWaiter.wait(for: [dropped], timeout: 3), .completed)
    }

    /// Filing a card from its hover menu adds the board chip to that card.
    @MainActor
    func testHoverBoardMenuAddsTheChip() throws {
        let (app, library) = try openLibrary()
        defer { app.terminate() }
        let ocean = cards(library).matching(NSPredicate(format: "label BEGINSWITH %@", "Ocean"))
            .firstMatch
        XCTAssertFalse(ocean.label.contains("Work"))
        ocean.hover()
        let board = library.descendants(matching: .any)["library-card-board"].firstMatch
        XCTAssertTrue(board.waitForExistence(timeout: 3))
        board.click()
        app.menuItems["Work"].firstMatch.click()
        let filed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "Work"), object: ocean)
        XCTAssertEqual(XCTWaiter.wait(for: [filed], timeout: 5), .completed)
    }

    /// Private Mode refuses every copy, so hover offers none.
    @MainActor
    func testPrivateModeOffersNoHoverCopy() throws {
        let (app, library) = try openLibrary(extra: [
            "-capture-preferences", Self.privateModePreferences
        ])
        defer { app.terminate() }
        cards(library).firstMatch.hover()
        XCTAssertTrue(library.buttons["library-card-pin"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertFalse(library.buttons["library-card-copy"].firstMatch.exists)
    }

    private static var privateModePreferences: String {
        let json =
            #"{"captureImages":true,"captureFileReferences":true,"captureRichText":true,"#
            + #""isPrivateModePaused":true,"privateModeStartedAt":"#
            + "\(Date.now.timeIntervalSinceReferenceDate)}"
        return "<" + Data(json.utf8).map { String(format: "%02x", $0) }.joined() + ">"
    }

    @MainActor
    func testListLayoutIsRememberedAcrossLaunches() throws {
        var (app, library) = try openLibrary()
        library.radioButtons["List"].firstMatch.click()
        XCTAssertTrue(library.radioButtons["List"].firstMatch.waitForSelection(true))
        waitForCards(6, in: library)
        app.terminate()

        (app, library) = try openLibrary(extra: ["-preserve-ui-test-defaults"])
        defer { app.terminate() }
        XCTAssertTrue(library.radioButtons["List"].firstMatch.waitForSelection(true))
    }

    /// The Pro meter reads the fullest ceiling (1 of 3 boards); snippets show
    /// their keyword and a new saved filter shows its count.
    @MainActor
    func testSidebarShowsTheMeterKeywordsAndFilterCounts() throws {
        let (app, library) = try openLibrary(extra: ["-seed-snippets"], cards: 8)
        defer { app.terminate() }
        let pro = library.descendants(matching: .any)["library-pro"].firstMatch
        XCTAssertTrue(pro.waitForExistence(timeout: 5))
        XCTAssertEqual(pro.value as? String, "33%")
        let keyword = library.descendants(matching: .any)
            .matching(identifier: "snippet-keyword").firstMatch
        XCTAssertTrue(keyword.waitForExistence(timeout: 5))

        library.buttons["saved-filter-new"].firstMatch.click()
        let name = app.textFields["filter-name-field"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        try typeTextReliably("Repos", into: name, in: app)
        try typeTextReliably(
            "github", into: app.textFields["filter-query-field"].firstMatch, in: app)
        app.buttons["filter-confirm"].firstMatch.click()
        // The row's id reaches its texts, the count included.
        let filterCount = library.staticTexts.matching(identifier: "saved-filter-row")
            .matching(NSPredicate(format: "label == '1' OR value == '1'")).firstMatch
        XCTAssertTrue(filterCount.waitForExistence(timeout: 5), "the new filter counts its clip")
    }
}

extension XCUIElement {
    /// A segmented control's segment reports its selection as its value.
    fileprivate func waitForSelection(_ selected: Bool, timeout: TimeInterval = 3) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", NSNumber(value: selected ? 1 : 0)),
            object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}

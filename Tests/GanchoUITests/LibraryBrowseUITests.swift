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
        XCTAssertTrue(app.textFields["search-field"].firstMatch.appears(within: 15))
        try SynthesizedInput.requireForeground(app)
        GanchoUITestCommands.post("library", token: nonce)
        let library = app.windows["Library"].firstMatch
        XCTAssertTrue(library.appears(within: 5))
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
    private func createSavedFilter(
        _ name: String, query: String, in app: XCUIApplication, library: XCUIElement
    ) throws {
        library.buttons["saved-filter-new"].firstMatch.click()
        let field = app.textFields["filter-name-field"].firstMatch
        XCTAssertTrue(field.appears(within: 3))
        try typeTextReliably(name, into: field, in: app)
        try typeTextReliably(
            query, into: app.textFields["filter-query-field"].firstMatch, in: app)
        app.buttons["filter-confirm"].firstMatch.click()
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

    /// The title names the scope and the kind mix adds up to its count on All
    /// clips and a board; Pinned and saved filters have no mix, and an idle
    /// sync has no caption.
    @MainActor
    func testHeaderNamesTheScopeAndItsKindMixAddsUp() throws {
        let (app, library) = try openLibrary()
        defer { app.terminate() }
        // Its header trait keeps it out of `staticTexts`.
        let title = library.descendants(matching: .any)["library-title"].firstMatch
        let count = library.staticTexts["library-scope-count"].firstMatch
        let mix = library.descendants(matching: .any)["library-kind-mix"].firstMatch
        XCTAssertTrue(title.waitForLabel("All clips"), title.label)
        try assertKindMix(
            mix, reads: "Kinds: 2 Images, 1 Links, 1 Code, 1 Colors, 1 Secrets", sumsTo: count)
        XCTAssertFalse(library.descendants(matching: .any)["sync-status"].exists)

        library.staticTexts.matching(
            NSPredicate(format: "identifier BEGINSWITH 'library-board-' AND value == 'Work'")
        )
        .firstMatch.click()
        waitForCards(1, in: library)
        XCTAssertTrue(title.waitForLabel("Work"))
        try assertKindMix(mix, reads: "Kinds: 1 Links", sumsTo: count)

        library.descendants(matching: .any)["library-pinned"].firstMatch.click()
        waitForCards(1, in: library)
        XCTAssertTrue(title.waitForLabel("Pinned"))
        XCTAssertFalse(mix.exists, "Pinned has no kind mix")

        try createSavedFilter("Repos", query: "github", in: app, library: library)
        let filter = library.staticTexts.matching(identifier: "saved-filter-row")
            .matching(NSPredicate(format: "label == 'Repos' OR value == 'Repos'")).firstMatch
        XCTAssertTrue(filter.appears(within: 5))
        filter.click()
        XCTAssertTrue(title.waitForLabel("Repos"))
        waitForCards(1, in: library)
        XCTAssertFalse(mix.exists, "a saved filter has no kind mix")
    }

    /// An up-to-date sync reads as the header's caps caption, not the generic
    /// status row. The forced state needs `-force-free-tier`, which `openLibrary` passes.
    @MainActor
    func testHeaderCaptionsAnUpToDateSync() throws {
        let (app, library) = try openLibrary(extra: ["-ui-test-sync-up-to-date"])
        defer { app.terminate() }
        let caption = library.staticTexts["sync-status"].firstMatch
        XCTAssertTrue(caption.appears(within: 3))
        XCTAssertEqual(caption.value as? String, "SYNCED")
    }

    /// The mix's spoken label, and its counts sum to the header's clip count.
    @MainActor
    private func assertKindMix(
        _ mix: XCUIElement, reads expected: String, sumsTo count: XCUIElement,
        file: StaticString = #filePath, line: UInt = #line
    ) throws {
        XCTAssertTrue(mix.waitForLabel(expected), mix.label, file: file, line: line)
        let leadingCount = { (text: Substring) in
            try XCTUnwrap(Int(text.prefix(while: \.isNumber)), file: file, line: line)
        }
        let total = try leadingCount(Substring(count.value as? String ?? ""))
        let sum = try mix.label.dropFirst("Kinds: ".count).split(separator: ", ")
            .map(leadingCount).reduce(0, +)
        XCTAssertEqual(sum, total, mix.label, file: file, line: line)
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
        XCTAssertTrue(copy.appears(within: 3))
        XCTAssertTrue(library.buttons["library-card-pin"].firstMatch.exists)
        XCTAssertTrue(library.descendants(matching: .any)["library-card-board"].firstMatch.exists)
        copy.click()
        XCTAssertTrue(app.staticTexts["Copied"].firstMatch.appears(within: 3))

        let secret = cards(library).matching(NSPredicate(format: "label BEGINSWITH %@", "Secret"))
            .firstMatch
        secret.hover()
        XCTAssertTrue(library.buttons["library-card-pin"].firstMatch.appears(within: 3))
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
        XCTAssertTrue(board.appears(within: 3))
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
        XCTAssertTrue(library.buttons["library-card-pin"].firstMatch.appears(within: 3))
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

    /// The Pro meter reads the fullest ceiling (1 of 3 boards) and is the only
    /// place for the ceilings; All clips and Pinned sit above Boards; snippets
    /// show their keyword and a new saved filter shows its count.
    @MainActor
    func testSidebarShowsTheMeterKeywordsAndFilterCounts() throws {
        let (app, library) = try openLibrary(extra: ["-seed-snippets"], cards: 8)
        defer { app.terminate() }
        let pro = library.descendants(matching: .any)["library-pro"].firstMatch
        XCTAssertTrue(pro.appears(within: 5))
        let value = try XCTUnwrap(pro.value as? String)
        XCTAssertTrue(value.hasPrefix("33%"), value)
        XCTAssertTrue(value.contains("1 of 3 boards"), "VoiceOver reads the ceilings: \(value)")
        XCTAssertEqual(pro.label, "gancho Pro")
        XCTAssertFalse(library.staticTexts["1/3"].exists, "the header repeats the meter")
        let allClips = library.descendants(matching: .any)["library-all-clips"].firstMatch
        let pinned = library.descendants(matching: .any)["library-pinned"].firstMatch
        let newBoard = library.buttons["board-new"].firstMatch
        let close = library.buttons[XCUIIdentifierCloseWindow].firstMatch
        XCTAssertTrue(allClips.exists && pinned.exists && newBoard.exists && close.exists)
        XCTAssertLessThan(pinned.frame.maxY, newBoard.frame.minY, "scopes sit above Boards")
        XCTAssertGreaterThan(
            allClips.frame.minY, close.frame.maxY, "the first row clears the traffic lights")
        let keyword = library.descendants(matching: .any)
            .matching(identifier: "snippet-keyword").firstMatch
        XCTAssertTrue(keyword.appears(within: 5))

        try createSavedFilter("Repos", query: "github", in: app, library: library)
        // The row's id reaches its texts, the count included.
        let filterCount = library.staticTexts.matching(identifier: "saved-filter-row")
            .matching(NSPredicate(format: "label == '1' OR value == '1'")).firstMatch
        XCTAssertTrue(filterCount.appears(within: 5), "the new filter counts its clip")
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

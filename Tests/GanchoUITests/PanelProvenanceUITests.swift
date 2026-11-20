import XCTest

/// The v4 panel's provenance header, scope counts and first-run lesson, over
/// synthetic clips or an empty throwaway store.
final class PanelProvenanceUITests: XCTestCase {
    private static let seededClips = 5

    @MainActor
    private func launch(seeded: Bool, extra: [String] = []) -> XCUIApplication {
        let app = GanchoUITestApplication()
        app.launchArguments =
            [
                "-open-panel-on-launch", "-use-in-process-status-item", "-use-temp-durable-store",
                "-force-free-tier", "-start-capture-paused", "-suppress-paused-notice-for-ui-test",
                "-opaque-panel-for-ui-test", "-place-panel-for-ui-test",
                "-suppress-storage-notice-for-ui-test", "-AppleLanguages", "(en)",
                "-ui-test-defaults-suite",
                "com.johnny4young.gancho.uitests.provenance.\(UUID().uuidString)"
            ] + (seeded ? ["-seed-visual-library", "-seed-peek-link"] : []) + extra
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
        XCTAssertTrue(link.appears(within: 15))
        link.click()

        let header = app.descendants(matching: .any)["peek-provenance"].firstMatch
        XCTAssertTrue(header.appears(within: 5))
        XCTAssertTrue(header.descendants(matching: .any)["peek-age"].firstMatch.exists)
        // Sync is off in UI tests, so the chip says nothing rather than guess.
        XCTAssertFalse(header.descendants(matching: .any)["peek-sync-state"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["preview-title"].firstMatch.exists)
        // The headline carries the decoded path; each parameter decodes in its own chip.
        let headline = app.staticTexts["peek-link-headline"].firstMatch
        XCTAssertTrue(headline.exists)
        let reading = headline.label.isEmpty ? headline.value as? String ?? "" : headline.label
        XCTAssertTrue(reading.contains("example.com/a/b"), reading)
        let decoded = app.descendants(matching: .any)["peek-link-decoded"].firstMatch
        let parameter = decoded.descendants(matching: .any)["peek-link-param-q"].firstMatch
        XCTAssertTrue(parameter.exists)
        XCTAssertEqual(parameter.value as? String, "a&b")
        XCTAssertTrue(
            app.descendants(matching: .any)["peek-link-part-host"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["peek-pastes-as"].firstMatch.exists)
    }

    /// At the Standard preset the link's anatomy reads on one line and every
    /// paste row sits above the dock without scrolling.
    @MainActor
    func testLinkPeekFitsAboveTheDockAtTheStandardPreset() throws {
        let app = launch(
            seeded: true, extra: ["-panel-content-width", "864", "-panel-content-height", "540"])
        defer { app.terminate() }
        let link = row("example.com", in: app)
        XCTAssertTrue(link.appears(within: 15))
        link.click()
        let dock = app.descendants(matching: .any)["peek-dock"].firstMatch
        XCTAssertTrue(dock.appears(within: 5))
        let host = app.descendants(matching: .any)["peek-link-part-host"].firstMatch
        XCTAssertTrue(host.appears(within: 5))
        for part in ["scheme", "path", "query", "fragment"] {
            let segment = app.descendants(matching: .any)["peek-link-part-\(part)"].firstMatch
            XCTAssertTrue(segment.exists, part)
            XCTAssertEqual(segment.frame.minY, host.frame.minY, accuracy: 1, part)
        }
        // A middle-truncated part still reads in full to VoiceOver.
        XCTAssertEqual(
            app.descendants(matching: .any)["peek-link-part-query"].firstMatch.value as? String,
            "?q=a%26b")
        for id in ["peek-pastes-as-return", "peek-pastes-as-plain", "peek-pastes-as-markdown"] {
            let pasteRow = app.descendants(matching: .any)[id].firstMatch
            XCTAssertTrue(pasteRow.exists, id)
            XCTAssertLessThanOrEqual(pasteRow.frame.maxY, dock.frame.minY, id)
        }
    }

    @MainActor
    func testMaskedClipHidesProvenance() throws {
        let app = launch(seeded: true)
        defer { app.terminate() }
        let masked = row("•••", in: app)
        XCTAssertTrue(masked.appears(within: 15))
        masked.click()
        let header = app.descendants(matching: .any)["peek-provenance"].firstMatch
        XCTAssertTrue(header.appears(within: 5))
        XCTAssertFalse(header.descendants(matching: .any)["peek-age"].firstMatch.exists)
        XCTAssertFalse(header.descendants(matching: .any)["peek-source-app"].firstMatch.exists)
    }

    @MainActor
    func testActiveScopeChipShowsTheBoardTotal() throws {
        let app = launch(seeded: true)
        defer { app.terminate() }
        let all = app.buttons["board-all"].firstMatch
        XCTAssertTrue(all.appears(within: 15))
        let counted = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", "All clips · \(Self.seededClips)"),
            object: all)
        XCTAssertEqual(XCTWaiter.wait(for: [counted], timeout: 10), .completed, all.label)
    }

    @MainActor
    private func waitForLabel(_ label: String, of element: XCUIElement) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label == %@", label), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: 10) == .completed
    }

    @MainActor
    func testScopeChipFollowsADeleteAndItsUndo() throws {
        let app = launch(seeded: true)
        defer { app.terminate() }
        let all = app.buttons["board-all"].firstMatch
        XCTAssertTrue(all.appears(within: 15))
        XCTAssertTrue(waitForLabel("All clips · \(Self.seededClips)", of: all), all.label)

        let link = row("example.com", in: app)
        XCTAssertTrue(link.appears(within: 5))
        link.rightClick()
        let delete = app.menuItems["Delete"].firstMatch
        XCTAssertTrue(delete.appears(within: 3))
        delete.click()
        XCTAssertTrue(waitForLabel("All clips · \(Self.seededClips - 1)", of: all), all.label)

        let undo = app.buttons["toast-undo"].firstMatch
        XCTAssertTrue(undo.appears(within: 5))
        undo.click()
        XCTAssertTrue(waitForLabel("All clips · \(Self.seededClips)", of: all), all.label)
    }

    @MainActor
    func testBoardChipCountsAClipAddedToIt() throws {
        let app = launch(seeded: true, extra: ["-seed-sample-boards"])
        defer { app.terminate() }
        let board = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Seed board 1 ·")
        ).firstMatch
        XCTAssertTrue(board.appears(within: 15))
        XCTAssertTrue(waitForLabel("Seed board 1 · 0", of: board), board.label)

        let link = row("example.com", in: app)
        XCTAssertTrue(link.appears(within: 5))
        link.rightClick()
        let menu = app.menuItems["Add to board"].firstMatch
        XCTAssertTrue(menu.appears(within: 3))
        menu.hover()
        let target = app.menuItems["Seed board 1"].firstMatch
        XCTAssertTrue(target.appears(within: 3))
        target.click()
        XCTAssertTrue(waitForLabel("Seed board 1 · 1", of: board), board.label)
    }

    @MainActor
    func testEmptyPanelTeachesThreeKeysAndOffersTheImporter() throws {
        let app = launch(seeded: false)
        defer { app.terminate() }
        let stage = app.descendants(matching: .any)["panel-first-run-stage"].firstMatch
        XCTAssertTrue(stage.appears(within: 15))
        let title = app.staticTexts["panel-empty-title"].firstMatch
        XCTAssertTrue(title.exists)
        XCTAssertEqual(AccessibleValue.text(of: title), "Nothing on the hook yet.")
        XCTAssertTrue(app.descendants(matching: .any)["panel-empty-mark"].firstMatch.exists)
        let importer = app.buttons["panel-empty-import-button"].firstMatch
        XCTAssertTrue(importer.appears(within: 5))
        importer.click()
        XCTAssertTrue(
            app.descendants(matching: .any)["migration-import-sheet"].firstMatch
                .appears(within: 5))
    }

    @MainActor
    func testLessonStaysGoneOnceAPasteHasLanded() throws {
        // A real number in the argument domain, as the paste-back stamp stores.
        let app = launch(seeded: false, extra: ["-first-pasteback-at", "<real>1</real>"])
        defer { app.terminate() }
        XCTAssertTrue(
            app.buttons["panel-empty-import-button"].firstMatch.appears(within: 15))
        XCTAssertFalse(app.descendants(matching: .any)["panel-first-run-stage"].firstMatch.exists)
    }
}

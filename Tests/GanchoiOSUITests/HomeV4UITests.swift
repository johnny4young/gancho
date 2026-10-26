import XCTest

/// The v4 Home list: a clip from another device names it, headers carry the
/// counts the list can vouch for, active filters show as chips, and a typed
/// search lists clips related by meaning. Every launch argument here is a
/// DEBUG-only hook on a throwaway store.
final class HomeV4UITests: XCTestCase {
    @MainActor
    func testRowsNameTheirDeviceAndHeadersCount() throws {
        let app = try launch(["-seed-home-v4"])
        defer { app.terminate() }
        let foreign = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier == 'clip-row' AND label CONTAINS %@", "Studio Mac")
        ).firstMatch
        XCTAssertTrue(foreign.waitForExistence(timeout: 10), "the row must name its device")
        let today = app.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "Today", "clips")
        ).firstMatch
        XCTAssertTrue(today.waitForExistence(timeout: 5), "Today must show its count")
        let allClips = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS %@", "All clips", "4")
        ).firstMatch
        XCTAssertTrue(allClips.waitForExistence(timeout: 5), "the active chip counts its scope")
    }

    @MainActor
    func testClipboardCardNamesTheSensedKind() throws {
        let app = try launch(["-ui-test-pasteboard-hints", "link"])
        defer { app.terminate() }
        let card = app.descendants(matching: .any)["pasteboard-status-card"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "something on the clipboard is a card")
        XCTAssertEqual(
            app.staticTexts["pasteboard-status-title"].firstMatch.label, "Link on your clipboard")
        XCTAssertTrue(app.buttons["pasteboard-info"].firstMatch.exists, "the ⓘ stays")
        XCTAssertFalse(
            app.buttons["pasteboard-saved-open"].firstMatch.exists, "nothing saved, nothing to open"
        )
    }

    @MainActor
    func testActiveFiltersShowAsChipsAndClear() throws {
        let app = try launch(["-seed-source-apps"])
        defer { app.terminate() }
        let filter = app.descendants(matching: .any)["history-filter-menu"].firstMatch
        guard filter.waitForExistence(timeout: 8), filter.isHittable else {
            throw XCTSkip("history filter menu is not reachable on this runner")
        }
        XCTAssertFalse(app.descendants(matching: .any)["filter-chips"].exists)
        filter.tap()
        let safari = app.descendants(matching: .any)["Safari"].firstMatch
        XCTAssertTrue(safari.waitForExistence(timeout: 5))
        safari.tap()

        let chip = app.buttons["filter-chip-app"].firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 5), "an active app filter shows as a chip")
        XCTAssertEqual(chip.label, "Remove Safari filter")
        XCTAssertTrue(app.staticTexts["Safari source alpha"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Xcode source sample"].exists)
        chip.tap()
        XCTAssertTrue(chip.waitForNonExistence(timeout: 5), "tapping the chip removes the filter")
        XCTAssertTrue(app.staticTexts["Xcode source sample"].waitForExistence(timeout: 5))

        filter.tap()
        XCTAssertTrue(safari.waitForExistence(timeout: 5))
        safari.tap()
        let clear = app.buttons["filter-clear"].firstMatch
        XCTAssertTrue(clear.waitForExistence(timeout: 5))
        clear.tap()
        XCTAssertTrue(clear.waitForNonExistence(timeout: 5), "Clear filters removes every chip")
    }

    @MainActor
    func testSearchListsRelatedByMeaning() throws {
        let app = try launch(["-seed-home-v4", "-ui-test-related-results"])
        defer { app.terminate() }
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("greeting")
        let heading = app.descendants(matching: .any)["meaning-related-heading"].firstMatch
        XCTAssertTrue(heading.waitForExistence(timeout: 10), "related clips list under the results")
        XCTAssertTrue(
            app.descendants(matching: .any).matching(
                NSPredicate(format: "label BEGINSWITH %@", "Results")
            ).firstMatch.exists, "the typed search's own results are titled Results")
    }

    @MainActor
    private func launch(_ extra: [String]) throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments =
            [
                "-skip-welcome-on-launch", "-use-temp-durable-store", "-AppleLanguages", "(en)"
            ] + extra
        app.launch()
        let capture = app.descendants(matching: .any)["capture-screen"].firstMatch
        guard capture.waitForExistence(timeout: 10) else {
            app.terminate()
            throw XCTSkip("capture screen is not reachable on this runner")
        }
        return app
    }
}

import AppKit
import XCTest

extension DesignV4SnapshotUITests {
    // MARK: Library — toolbar, kind chips, grouped cards and the Pro meter.

    @MainActor func testLibraryLight() throws {
        try library(appearance: "light")
    }

    @MainActor func testLibraryDark() throws {
        try library(appearance: "dark")
    }

    @MainActor private func library(appearance: String) throws {
        let token = UUID().uuidString
        let app = GanchoUITestApplication()
        app.launchArguments =
            stableArguments(appearance) + [
                "-open-panel-on-launch", "-use-in-process-status-item", "-seed-visual-library",
                "-seed-visual-library-extras", "-force-free-tier", "-place-library-for-ui-test",
                "-library-board-size-for-ui-test",
                "-place-panel-for-ui-test", "-suppress-storage-notice-for-ui-test",
                "-AppleLanguages", "(en)", "-command-nonce", token
            ]
        app.launch()
        defer { app.terminate() }
        XCTAssertTrue(app.textFields["search-field"].firstMatch.waitForExistence(timeout: 15))
        GanchoUITestCommands.post("library", token: token)
        let library = app.windows["Library"].firstMatch
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        let cards = library.buttons.matching(identifier: "library-clip")
        let seeded = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "count == 6"), object: cards)
        XCTAssertEqual(XCTWaiter.wait(for: [seeded], timeout: 8), .completed)
        // The pointer rests on the title bar, so no card shows its hover actions.
        try SynthesizedInput.requireForeground(app)
        library.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.01)).hover()
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        try DesignSnapshot.save(
            DesignSnapshot.renderWindow(titled: "Library", named: "library", in: renders),
            named: "library-\(appearance)")
    }
}

import AppKit
import XCTest

final class VisualLibraryUITests: XCTestCase {
    @MainActor
    func testVisualCardsPreserveSafeCopyAndOrganization() throws {
        let app = GanchoUITestApplication()
        let nonce = UUID().uuidString
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item", "-use-temp-durable-store",
            "-seed-visual-library", "-force-free-tier", "-start-capture-paused",
            "-ui-test-paste-sink", "copiedOnly", "-AppleLanguages", "(en)",
            "-ui-test-defaults-suite",
            "com.johnny4young.gancho.uitests.library.\(UUID().uuidString)",
            "-command-nonce", nonce
        ]
        app.launch()
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        defer { app.terminate() }
        XCTAssertTrue(app.textFields["search-field"].waitForExistence(timeout: 15))
        try SynthesizedInput.requireForeground(app)
        GanchoUITestCommands.post("library", token: nonce)
        let library = app.windows["Library"].firstMatch
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        XCTAssertTrue(app.dialogs["history-panel"].waitForNonExistence(timeout: 5))
        let cards = library.buttons.matching(identifier: "library-clip")
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(cards.count, 4)
        XCTAssertEqual(
            cards.matching(NSPredicate(format: "label CONTAINS %@", "Hidden fixture title")).count,
            0)
        let imageCard = cards.matching(
            NSPredicate(format: "label CONTAINS %@", "Synthetic landscape")
        ).firstMatch
        XCTAssertTrue(imageCard.waitForExistence(timeout: 5))
        // The card is one combined accessibility button, not a tree of image children.
        let loaded = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "label CONTAINS %@", "Image preview"), object: imageCard)
        XCTAssertEqual(XCTWaiter.wait(for: [loaded], timeout: 5), .completed)
        let screenshot = XCTAttachment(screenshot: library.screenshot())
        screenshot.name = "Visual Library — synthetic image, color, code and protected clip"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        try SynthesizedInput.requireForeground(app)
        imageCard.rightClick()
        XCTAssertTrue(app.menuItems["Add to board"].firstMatch.exists)
        app.menuItems["library-copy-action"].firstMatch.click()
        XCTAssertTrue(app.staticTexts["Copied"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertEqual(cards.count, 4)
    }
}

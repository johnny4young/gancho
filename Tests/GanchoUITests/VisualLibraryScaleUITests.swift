import AppKit
import XCTest

final class VisualLibraryScaleUITests: XCTestCase {
    @MainActor
    func testScrollsTwoThousandImagesAndReloadsEvictedThumbnails() throws {
        continueAfterFailure = false
        let app = GanchoUITestApplication()
        let nonce = UUID().uuidString
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item", "-use-temp-durable-store",
            "-seed-visual-library", "-seed-visual-library-scale", "-force-free-tier",
            "-start-capture-paused", "-ui-test-paste-sink", "copiedOnly",
            "-ui-test-defaults-suite", "com.johnny4young.gancho.uitests.library-scale.\(UUID())",
            "-command-nonce", nonce, "-AppleLanguages", "(en)"
        ]
        app.launch()
        app.activate()
        defer { app.terminate() }
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        // Seeding writes real encrypted multi-megapixel fixtures, not a mocked count.
        XCTAssertTrue(app.textFields["search-field"].waitForExistence(timeout: 60))
        try SynthesizedInput.requireForeground(app)
        GanchoUITestCommands.post("library", token: nonce)
        let library = app.windows["Library"].firstMatch
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        let count = library.staticTexts["library-scope-count"]
        XCTAssertTrue(waitForCount([100], in: count), "Initial loading must remain paged")
        let scroll = library.scrollViews["library-clips-scroll"]
        XCTAssertTrue(scroll.exists)

        var loadedCount = 100
        for _ in 0..<20 where loadedCount < 2_000 {
            try SynthesizedInput.requireForeground(app)
            scroll.scroll(byDeltaX: 0, deltaY: -30_000)
            // A long wheel gesture may legitimately traverse several pages.
            let nextPages = Array(stride(from: loadedCount + 100, through: 2_000, by: 100))
            XCTAssertTrue(
                waitForCount(nextPages, in: count),
                "Scrolling must advance whole pages without exceeding the fixture count")
            let value = count.value as? String ?? count.label
            loadedCount = try XCTUnwrap(Int(value.filter(\.isNumber)))
        }
        XCTAssertEqual(loadedCount, 2_000)
        let cards = library.buttons.matching(identifier: "library-clip")
        let last = cards.matching(
            NSPredicate(format: "label CONTAINS %@", "Synthetic scale image 1999")
        ).firstMatch
        scroll.scroll(byDeltaX: 0, deltaY: -30_000)
        XCTAssertTrue(last.waitForHittable(timeout: 5))
        XCTAssertTrue(waitForPreview(in: last))

        let first = cards.matching(
            NSPredicate(format: "label CONTAINS %@", "Synthetic scale image 0")
        ).firstMatch
        for _ in 0..<8 where !first.isHittable {
            scroll.scroll(byDeltaX: 0, deltaY: 30_000)
        }
        XCTAssertTrue(first.waitForHittable(timeout: 5))
        XCTAssertTrue(
            waitForPreview(in: first), "Returning after cache eviction must reload the preview")
        XCTAssertTrue(waitForCount([2_000], in: count))
        let attachment = XCTAttachment(screenshot: library.screenshot())
        attachment.name = "Visual Library — 2000 synthetic images after scrolling back"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func waitForCount(_ counts: [Int], in element: XCUIElement) -> Bool {
        // English UI can still use the host region's grouping separator.
        let numbers = counts.map { count in
            count < 1_000
                ? String(count)
                : "\(count / 1_000)[.,\\s]?\(String(format: "%03d", count % 1_000))"
        }
        let expected = "(?:\(numbers.joined(separator: "|"))) clips"
        let predicate = NSPredicate(
            format: "label MATCHES %@ OR value MATCHES %@", expected, expected)
        return XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 5)
            == .completed
    }

    @MainActor
    private func waitForPreview(in element: XCUIElement) -> Bool {
        let predicate = NSPredicate(format: "label CONTAINS %@", "Image preview")
        return XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: element)], timeout: 5)
            == .completed
    }
}

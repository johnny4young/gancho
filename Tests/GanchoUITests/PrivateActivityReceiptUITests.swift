import XCTest

/// Durable, content-free receipt smoke over the real macOS Privacy Center.
/// The seed hook requires a throwaway store and cannot touch user history.
final class PrivateActivityReceiptUITests: XCTestCase {
    @MainActor
    func testReceiptRendersAndClearsIndependently() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-regular-activation-for-ui-tests", "-use-in-process-status-item",
            "-use-temp-durable-store", "-seed-private-activity-receipt",
            "-open-privacy-center-on-launch", "-force-capture-active",
            "-disable-screen-share-auto-pause", "-force-pasteboard-access-allowed",
            "-ui-test-defaults-suite", "com.johnny4young.gancho.uitests.\(UUID().uuidString)",
            "-AppleLanguages", "(en)"
        ]
        app.launch()
        defer { app.terminate() }
        app.activate()
        guard app.wait(for: .runningForeground, timeout: 5) else {
            throw XCTSkip("Gancho did not reach the foreground")
        }

        let receipt = app.descendants(matching: .any)["private-receipt-section"].firstMatch
        XCTAssertTrue(receipt.waitForExistence(timeout: 8))
        XCTAssertTrue(value(of: "private-receipt-reused-count", in: app).contains("8"))
        XCTAssertTrue(value(of: "private-receipt-captured-count", in: app).contains("12"))
        XCTAssertTrue(value(of: "private-receipt-skipped-count", in: app).contains("3"))
        XCTAssertTrue(value(of: "private-receipt-protected-count", in: app).contains("2"))

        let attachment = XCTAttachment(screenshot: app.windows["Privacy Center"].screenshot())
        attachment.name = "macOS private activity receipt"
        attachment.lifetime = .keepAlways
        add(attachment)

        let clear = app.buttons["clear-private-receipt-button"].firstMatch
        XCTAssertTrue(clear.waitForExistence(timeout: 3))
        app.activate()
        guard clear.isHittable else {
            throw XCTSkip("Another desktop window obscured the receipt clear action")
        }
        clear.click()
        // SwiftUI presents macOS alerts as window sheets in the AX hierarchy.
        let confirmation = app.sheets.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
        confirmation.buttons["Clear receipt"].click()

        let reused = app.descendants(matching: .any)["private-receipt-reused-count"].firstMatch
        let cleared = XCTNSPredicateExpectation(
            predicate: NSPredicate { element, _ in
                guard let element = element as? XCUIElement else { return false }
                let text =
                    (element.value as? String).flatMap { $0.isEmpty ? nil : $0 }
                    ?? element.label
                return text.contains("0")
            },
            object: reused)
        XCTAssertEqual(XCTWaiter().wait(for: [cleared], timeout: 5), .completed)
        XCTAssertTrue(value(of: "private-receipt-captured-count", in: app).contains("0"))
    }

    @MainActor
    private func value(of identifier: String, in app: XCUIApplication) -> String {
        let element = app.descendants(matching: .any)[identifier].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Missing element: \(identifier)")
        return (element.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? element.label
    }
}

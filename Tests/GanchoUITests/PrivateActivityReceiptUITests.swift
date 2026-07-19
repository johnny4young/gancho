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
        XCTAssertEqual(count(of: "private-receipt-reused-count", in: app), 8)
        XCTAssertEqual(count(of: "private-receipt-captured-count", in: app), 12)
        XCTAssertEqual(count(of: "private-receipt-skipped-count", in: app), 3)
        XCTAssertEqual(count(of: "private-receipt-protected-count", in: app), 2)
        XCTAssertTrue(
            app.descendants(matching: .any)["private-receipt-app-0-row"].firstMatch
                .waitForExistence(timeout: 3))
        XCTAssertTrue(
            app.descendants(matching: .any)["private-receipt-app-1-row"].firstMatch
                .waitForExistence(timeout: 3))

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
        let confirmation = app.windows["Privacy Center"].sheets.firstMatch
        XCTAssertTrue(confirmation.waitForExistence(timeout: 3))
        confirmation.buttons["Clear receipt"].click()

        let reused = app.descendants(matching: .any)["private-receipt-reused-count"].firstMatch
        let cleared = XCTNSPredicateExpectation(
            predicate: NSPredicate { element, _ in
                guard let element = element as? XCUIElement else { return false }
                return Self.integer(in: Self.accessibleText(of: element)) == 0
            },
            object: reused)
        XCTAssertEqual(XCTWaiter().wait(for: [cleared], timeout: 5), .completed)
        XCTAssertEqual(count(of: "private-receipt-captured-count", in: app), 0)
    }

    @MainActor
    private func value(of identifier: String, in app: XCUIApplication) -> String {
        let element = app.descendants(matching: .any)[identifier].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Missing element: \(identifier)")
        return Self.accessibleText(of: element)
    }

    @MainActor
    private func count(of identifier: String, in app: XCUIApplication) -> Int? {
        Self.integer(in: value(of: identifier, in: app))
    }

    @MainActor
    private static func accessibleText(of element: XCUIElement) -> String {
        (element.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? element.label
    }

    private static func integer(in text: String) -> Int? {
        text.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.first
    }
}

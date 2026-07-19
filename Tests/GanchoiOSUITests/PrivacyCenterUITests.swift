import XCTest

/// iOS UI smoke for the Privacy Center error log — the iOS sibling of the macOS
/// `PanelUITests` coverage. XCTest lives ONLY in UI-test targets; package unit
/// tests use Swift Testing.
final class PrivacyCenterUITests: XCTestCase {
    @MainActor
    func testPrivateActivityReceiptRendersAndClears() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-use-temp-durable-store", "-seed-private-activity-receipt",
            "-open-privacy-center-on-launch", "-AppleLanguages", "(en)"
        ]
        app.launch()
        defer { app.terminate() }

        let privacyCenter = app.descendants(matching: .any)["ios-privacy-center"].firstMatch
        XCTAssertTrue(privacyCenter.waitForExistence(timeout: 10))
        let reused = app.descendants(matching: .any)[
            "ios-private-receipt-reused-count"
        ].firstMatch
        XCTAssertTrue(reused.waitForExistence(timeout: 5))
        XCTAssertEqual(integerValue(of: reused), 8)
        XCTAssertEqual(count(of: "ios-private-receipt-captured-count", in: app), 12)
        XCTAssertEqual(count(of: "ios-private-receipt-skipped-count", in: app), 2)
        XCTAssertEqual(count(of: "ios-private-receipt-protected-count", in: app), 2)
        XCTAssertTrue(
            app.descendants(matching: .any)["ios-private-receipt-app-0-row"].firstMatch
                .waitForExistence(timeout: 3))
        let secondApp = app.descendants(matching: .any)[
            "ios-private-receipt-app-1-row"
        ].firstMatch
        for _ in 0..<3 where !secondApp.exists { privacyCenter.swipeUp() }
        XCTAssertTrue(secondApp.waitForExistence(timeout: 3))

        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "iOS private activity receipt"
        attachment.lifetime = .keepAlways
        add(attachment)

        let clear = app.buttons["ios-clear-private-receipt-button"].firstMatch
        // Return the lazy Form to its resting top position. A merely hittable
        // row can still sit beneath the translucent navigation bar after one
        // reverse swipe, where XCTest synthesizes a tap without firing it.
        for _ in 0..<3 { privacyCenter.swipeDown() }
        XCTAssertTrue(clear.waitForExistence(timeout: 3))
        XCTAssertTrue(clear.isHittable)
        clear.tap()
        let alert = app.alerts["Clear activity receipt?"].firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 3))
        alert.buttons["Clear receipt"].tap()

        let cleared = XCTNSPredicateExpectation(
            predicate: NSPredicate { element, _ in
                guard let element = element as? XCUIElement else { return false }
                return Self.integer(in: Self.accessibleText(of: element)) == 0
            },
            object: reused)
        XCTAssertEqual(XCTWaiter().wait(for: [cleared], timeout: 5), .completed)
        XCTAssertEqual(count(of: "ios-private-receipt-captured-count", in: app), 0)
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
    private func integerValue(of element: XCUIElement) -> Int? {
        Self.integer(in: Self.accessibleText(of: element))
    }

    @MainActor
    private static func accessibleText(of element: XCUIElement) -> String {
        (element.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? element.label
    }

    private static func integer(in text: String) -> Int? {
        text.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.first
    }

    @MainActor
    func testPrivacyCenterRecentIssuesLogsEphemeralStorage() {
        // Force the in-memory fallback so the model logs a content-free
        // "Storage" issue at construction, and route straight to the Privacy
        // Center (no welcome, no navigation).
        let app = XCUIApplication()
        app.launchArguments = ["-force-ephemeral-store", "-open-privacy-center-on-launch"]
        app.launch()
        defer { app.terminate() }

        let privacyCenter = app.descendants(matching: .any)["ios-privacy-center"].firstMatch
        XCTAssertTrue(
            privacyCenter.waitForExistence(timeout: 10),
            "the -open-privacy-center-on-launch hook must show the Privacy Center")
        let successfulReuse = app.descendants(matching: .any)[
            "ios-successful-reuse-count"
        ].firstMatch
        for _ in 0..<6 {
            if successfulReuse.waitForExistence(timeout: 1) { break }
            privacyCenter.swipeUp()
        }
        XCTAssertTrue(
            successfulReuse.waitForExistence(timeout: 5),
            "the Privacy Center must expose the in-memory successful-reuse count")

        // The ephemeral-store launch logged an issue, so the "Recent issues"
        // section must surface it with the Copy-for-support button — the
        // end-to-end proof that the error log records and renders on iOS.
        let copyButton = app.buttons["copy-diagnostics"].firstMatch
        for _ in 0..<8 {
            if copyButton.waitForExistence(timeout: 1) { break }
            privacyCenter.swipeUp()
        }
        XCTAssertTrue(
            copyButton.waitForExistence(timeout: 5),
            "an ephemeral-store launch must log a content-free issue shown in Recent issues")
    }

    @MainActor
    func testTelemetryConsentStartsDisabledAndCanBeDeclined() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-skip-welcome-on-launch", "-force-ephemeral-store",
            "-show-telemetry-consent", "-telemetry-consent", "notAsked",
            "-AppleLanguages", "(en)"
        ]
        app.launch()
        defer { app.terminate() }

        let alert = app.alerts["Help improve Gancho?"].firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        alert.buttons["Keep disabled"].tap()
        XCTAssertFalse(alert.waitForExistence(timeout: 1))
    }
}

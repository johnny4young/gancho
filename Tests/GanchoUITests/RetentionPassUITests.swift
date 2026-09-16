import XCTest

/// The SCHEDULED retention pass, end to end on the real macOS store and Privacy
/// Center. The seed only inserts a sensitive clip created long before the
/// sensitive lifetime; what expires it is the pass `AppModel` starts at launch,
/// which waits for that insert first. So a receipt entry here is evidence that
/// the scheduled path ran, not that a test called the pass itself.
///
/// Capture stays paused: this test never needs the pasteboard, and a UI test has
/// no business reading the developer's clipboard into a store on disk.
final class RetentionPassUITests: XCTestCase {
    @MainActor
    func testTheLaunchPassCountsTheSeededSecretOnTheReceipt() throws {
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-regular-activation-for-ui-tests", "-use-in-process-status-item",
            "-use-temp-durable-store", "-seed-expired-sensitive-clip",
            "-open-privacy-center-on-launch", "-start-capture-paused",
            "-ui-test-defaults-suite", "com.johnny4young.gancho.uitests.\(UUID().uuidString)",
            "-AppleLanguages", "(en)"
        ]
        app.launch()
        defer { app.terminate() }
        app.activate()
        guard app.wait(for: .runningForeground, timeout: 5) else {
            throw XCTSkip("Gancho did not reach the foreground")
        }

        let expired = app.descendants(matching: .any)["private-receipt-expired-count"].firstMatch
        XCTAssertTrue(expired.waitForExistence(timeout: 10), "the receipt must render")
        // The receipt loads asynchronously, so wait for the count rather than
        // reading it once.
        let counted = XCTNSPredicateExpectation(
            predicate: NSPredicate { element, _ in
                guard let element = element as? XCUIElement else { return false }
                return AccessibleValue.firstInteger(in: AccessibleValue.text(of: element)) == 1
            },
            object: expired)
        XCTAssertEqual(
            XCTWaiter().wait(for: [counted], timeout: 5), .completed,
            "exactly the one seeded secret must have expired through the launch pass")

        // Element-scoped: the counted value, never the rest of the desktop.
        let attachment = XCTAttachment(screenshot: expired.screenshot())
        attachment.name = "macOS receipt after the launch retention pass"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

import XCTest

/// The Privacy Center opens on its proofs, and Verify checks the store on this Mac.
final class PrivacyCenterVerifyUITests: XCTestCase {
    @MainActor
    func testVerifyGroupComesFirstAndVerifiesTheStore() throws {
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-regular-activation-for-ui-tests", "-use-in-process-status-item",
            "-use-temp-durable-store", "-open-privacy-center-on-launch", "-start-capture-paused",
            "-ui-test-defaults-suite", "com.johnny4young.gancho.uitests.\(UUID().uuidString)",
            "-AppleLanguages", "(en)"
        ]
        app.launch()
        defer { app.terminate() }
        app.activate()
        let verify = app.buttons["privacy-verify-encryption"].firstMatch
        XCTAssertTrue(verify.waitForExistence(timeout: 10))
        let receipt = app.descendants(matching: .any)["private-receipt-section"].firstMatch
        XCTAssertTrue(receipt.waitForExistence(timeout: 5))
        XCTAssertLessThan(verify.frame.minY, receipt.frame.minY, "Verify sits above the receipt")

        verify.click()
        let result = app.descendants(matching: .any)["privacy-verify-result"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        let passed = XCTNSPredicateExpectation(
            predicate: NSPredicate(
                format: "label BEGINSWITH %@ OR value BEGINSWITH %@", "Verified", "Verified"),
            object: result)
        XCTAssertEqual(XCTWaiter.wait(for: [passed], timeout: 3), .completed, result.label)
    }
}

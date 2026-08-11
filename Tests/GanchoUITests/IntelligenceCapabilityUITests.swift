import XCTest

/// The supported Sequoia floor, exercised deterministically on any host OS:
/// `-simulate-sequoia-capabilities` forces the pre-26 capability answer, and
/// the Intelligence window must explain that model-backed features require
/// macOS 26 — a fact about this OS, not a generic "Apple Intelligence is off".
final class IntelligenceCapabilityUITests: XCTestCase {
    @MainActor
    func testSimulatedSequoiaExplainsTheMacOS26Requirement() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-regular-activation-for-ui-tests", "-use-in-process-status-item",
            "-use-temp-durable-store", "-start-capture-paused",
            "-ui-test-defaults-suite",
            "com.johnny4young.gancho.uitests.intelligence-capability",
            "-open-deep-link-on-launch", "gancho://settings",
            "-simulate-sequoia-capabilities",
            "-AppleLanguages", "(en)"
        ]
        app.launch()
        defer { app.terminate() }

        let settings = app.windows["Settings"].firstMatch
        XCTAssertTrue(settings.waitForExistence(timeout: 8))

        let captureTab = app.buttons["settings-tab-capture"].firstMatch
        XCTAssertTrue(captureTab.waitForExistence(timeout: 3))
        captureTab.click()

        let openIntelligence = app.buttons["open-intelligence"].firstMatch
        XCTAssertTrue(openIntelligence.waitForExistence(timeout: 3))
        openIntelligence.click()

        let intelligence = app.windows["Intelligence"].firstMatch
        XCTAssertTrue(intelligence.waitForExistence(timeout: 5))

        let notice = intelligence.descendants(matching: .any)
            .matching(identifier: "intelligence-capability-notice").firstMatch
        XCTAssertTrue(notice.waitForExistence(timeout: 3))
        // SwiftUI exposes static text through `value` on macOS, while other
        // accessibility roles may expose the same content through `label`.
        let noticeText = "\(notice.label) \(notice.value as? String ?? "")"
        XCTAssertTrue(
            noticeText.contains("macOS 26"),
            "the Sequoia notice must name the real requirement, got: \(noticeText)")
    }
}

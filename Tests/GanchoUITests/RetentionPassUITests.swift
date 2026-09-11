import XCTest

/// The shared retention pass, end to end on the real macOS store and Privacy
/// Center. The seed inserts one synthetic sensitive clip created long before the
/// sensitive lifetime and waits for a real pass, so the receipt's expiry count
/// can only come from that pass: nothing records it directly.
final class RetentionPassUITests: XCTestCase {
    @MainActor
    func testExpiredSensitiveClipIsPurgedAndCountedOnTheReceipt() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-regular-activation-for-ui-tests", "-use-in-process-status-item",
            "-use-temp-durable-store", "-seed-expired-sensitive-clip",
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

        let expired = app.descendants(matching: .any)["private-receipt-expired-count"].firstMatch
        XCTAssertTrue(expired.waitForExistence(timeout: 10), "the receipt must render")
        // The receipt loads asynchronously; give it a moment to show the pass.
        let deadline = Date().addingTimeInterval(5)
        while Self.integer(in: Self.accessibleText(of: expired)) != 1, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        XCTAssertEqual(
            Self.integer(in: Self.accessibleText(of: expired)), 1,
            "exactly the one seeded secret must have expired through the pass")

        // Element-scoped: the counted value, never the rest of the desktop.
        let attachment = XCTAttachment(screenshot: expired.screenshot())
        attachment.name = "macOS receipt after a retention pass"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private static func accessibleText(of element: XCUIElement) -> String {
        (element.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? element.label
    }

    private static func integer(in text: String) -> Int? {
        Int(text.filter(\.isNumber))
    }
}

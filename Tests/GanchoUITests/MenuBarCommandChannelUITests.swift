import Foundation
import XCTest

/// Black-box coverage for the content-free helper-to-app command channel.
/// The helper carries only a command name and the current launch nonce; private
/// clipboard state remains exclusively in the Gancho process.
final class MenuBarCommandChannelUITests: XCTestCase {
    @MainActor
    func testValidNonceOpensSettingsWindow() {
        let token = UUID().uuidString
        let app = launch(commandNonce: token)
        defer { app.terminate() }

        postCommand("settings", token: token)

        XCTAssertTrue(app.windows["Settings"].firstMatch.waitForExistence(timeout: 5))
    }

    @MainActor
    func testWrongNonceIsIgnored() {
        let app = launch(commandNonce: UUID().uuidString)
        defer { app.terminate() }

        postCommand("settings", token: UUID().uuidString)

        XCTAssertFalse(app.windows["Settings"].firstMatch.waitForExistence(timeout: 3))
    }

    @MainActor
    private func launch(commandNonce: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-open-panel-on-launch", "-use-in-process-status-item",
            "-command-nonce", commandNonce
        ]
        app.launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        return app
    }

    private func postCommand(_ command: String, token: String) {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.johnny4young.gancho.menu-bar-command.\(command)"),
            object: token,
            userInfo: nil,
            options: [.deliverImmediately])
    }
}

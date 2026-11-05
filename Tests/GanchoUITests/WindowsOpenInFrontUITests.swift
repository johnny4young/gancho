import AppKit
import XCTest

/// Menu-bar commands arrive while another app is active, and the window asked
/// for must end up above it with the keyboard.
final class WindowsOpenInFrontUITests: XCTestCase {
    private static let nonce = "windows-open-in-front"
    private static let windows = [
        ("settings", "Settings"), ("library", "Library"), ("privacyCenter", "Privacy Center"),
        ("welcome", "Welcome to Gancho"), ("fixClipboardAccess", "Clipboard Access")
    ]

    @MainActor
    func testMenuBarCommandsOpenTheirWindowOverTheActiveApp() throws {
        continueAfterFailure = false
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-use-in-process-status-item", "-command-nonce", Self.nonce,
            "-has-seen-welcome", "YES", "-start-capture-paused", "-AppleLanguages", "(en)"
        ]
        app.launch()
        defer { app.terminate() }
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")

        for (command, title) in Self.windows {
            finder.activate()
            XCTAssertTrue(finder.wait(for: .runningForeground, timeout: 10), command)
            GanchoUITestCommands.post(command, token: Self.nonce)
            XCTAssertTrue(app.windows[title].firstMatch.waitForExistence(timeout: 10), title)
            XCTAssertTrue(
                app.wait(for: .runningForeground, timeout: 5), "\(title) takes the keyboard")
            XCTAssertEqual(frontWindowOwner(), "Gancho", "\(title) opens above the active app")
        }
    }

    /// The window server's order: no pixels are captured.
    @MainActor
    private func frontWindowOwner() -> String? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
        return list.lazy.filter { $0[kCGWindowLayer as String] as? Int == 0 }
            .compactMap { $0[kCGWindowOwnerName as String] as? String }
            .first { $0 == "Gancho" || $0 == "Finder" }
    }
}

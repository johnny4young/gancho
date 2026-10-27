import XCTest

/// Pure checks of the menu-bar command deep link; no app launch.
final class MenuBarDeepLinkTests: XCTestCase {
    private let nonce = "launch-nonce"

    private func url(_ string: String) throws -> URL {
        try XCTUnwrap(URL(string: string))
    }

    func testAcceptsACommandCarryingThisLaunchsNonce() throws {
        XCTAssertEqual(
            GanchoMenuBarCommand.authorized(
                try url("gancho://menu-bar/settings?token=\(nonce)"), nonce: nonce),
            .settings)
    }

    func testRejectsAMissingOrForeignNonce() throws {
        XCTAssertNil(
            GanchoMenuBarCommand.authorized(try url("gancho://menu-bar/settings"), nonce: nonce))
        XCTAssertNil(
            GanchoMenuBarCommand.authorized(
                try url("gancho://menu-bar/settings?token=forged"), nonce: nonce))
    }

    func testRejectsOtherHostsAndUnknownCommands() throws {
        XCTAssertNil(
            GanchoMenuBarCommand.authorized(
                try url("gancho://settings?token=\(nonce)"), nonce: nonce))
        XCTAssertNil(
            GanchoMenuBarCommand.authorized(
                try url("gancho://menu-bar/not-a-command?token=\(nonce)"), nonce: nonce))
    }
}

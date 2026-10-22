import AppKit
import XCTest

/// Pure checks of the helper bridge encoding; no app launch. XCTest because
/// UI test bundles cannot import Swift Testing.
final class MenuBarKeyEquivalentTests: XCTestCase {
    func testRoundTripsThroughTheBridgeValue() throws {
        let shortcut = try XCTUnwrap(
            MenuBarKeyEquivalent(key: "v", modifiers: [.command, .option]))
        XCTAssertEqual(MenuBarKeyEquivalent(bridgeValue: shortcut.bridgeValue), shortcut)
    }

    func testMissingOrEmptyKeyMeansNoShortcut() {
        XCTAssertNil(MenuBarKeyEquivalent(key: nil, modifiers: [.command]))
        XCTAssertNil(MenuBarKeyEquivalent(key: "", modifiers: [.command]))
        XCTAssertNil(MenuBarKeyEquivalent(bridgeValue: nil))
        XCTAssertNil(MenuBarKeyEquivalent(bridgeValue: ["key": "v"]))
    }

    func testDropsDeviceDependentModifierBits() throws {
        let raw = NSEvent.ModifierFlags.command.rawValue | 0x10
        let shortcut = try XCTUnwrap(
            MenuBarKeyEquivalent(key: "v", modifiers: NSEvent.ModifierFlags(rawValue: raw)))
        XCTAssertEqual(shortcut.modifiers, [.command])
    }

    @MainActor func testAppliesToAMenuItem() throws {
        let item = NSMenuItem(title: "Open panel", action: nil, keyEquivalent: "")
        try XCTUnwrap(MenuBarKeyEquivalent(key: "v", modifiers: [.command, .option]))
            .apply(to: item)
        XCTAssertEqual(item.keyEquivalent, "v")
        XCTAssertEqual(item.keyEquivalentModifierMask, [.command, .option])
    }
}

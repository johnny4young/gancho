import AppKit
import XCTest

final class ShortcutMenuUITests: XCTestCase {
    @MainActor
    func testConsumedMenuShortcutIsDeliveredOnceWithoutRequeue() async throws {
        let environment = ProcessInfo.processInfo.environment
        let snapshotPath = try XCTUnwrap(environment["SHORTCUT_MENU_SNAPSHOT"])
        let bundleIdentifier = try XCTUnwrap(environment["SHORTCUT_MENU_BUNDLE_ID"])
        let app = XCUIApplication(bundleIdentifier: bundleIdentifier)
        app.launchArguments = ["-fixture-snapshot", snapshotPath]
        app.launch()
        defer { app.terminate() }
        let windowExists = try await waitForElement(
            app.windows["Shortcut Menu Fixture"], seconds: 8)
        guard windowExists else {
            XCTFail("The fixture window did not appear")
            return
        }
        let initial = try await waitForSnapshot(at: snapshotPath) { $0["version"] != nil }
        guard
            initial["version"] as? String == environment["SHORTCUT_MENU_VERSION"],
            initial["revision"] as? String == environment["SHORTCUT_MENU_REVISION"],
            initial["bundleIdentifier"] as? String == bundleIdentifier
        else {
            XCTFail("The fixture snapshot does not match the canonical dependency and identity")
            return
        }
        try requireRegisteredChord(initial)

        try requireForeground(app, bundleIdentifier: bundleIdentifier)
        let openMenu = app.buttons["open-menu-button"]
        guard openMenu.isHittable else {
            XCTFail("The fixture menu button is not hittable")
            return
        }
        openMenu.click()
        let menuExists = try await waitForElement(
            app.menuItems["Reserved Fixture Action"], seconds: 3)
        guard menuExists else {
            XCTFail("The fixture menu did not appear")
            return
        }
        let tracking = try await waitForSnapshot(at: snapshotPath) {
            $0["menuTracking"] as? Bool == true
        }
        guard tracking["menuTracking"] as? Bool == true else {
            XCTFail("The fixture is not tracking its popup menu")
            return
        }

        // XCUITest synthesizes global input; abort if the fixture loses focus.
        try requireForeground(app, bundleIdentifier: bundleIdentifier)
        app.typeKey("v", modifierFlags: [.command, .control, .option, .shift])
        let during = try await waitForSnapshot(at: snapshotPath) {
            $0["keyDownCount"] as? Int == 1 && $0["keyUpCount"] as? Int == 1
        }
        try attach(during, name: "menu-after-one-native-key-pair")
        XCTAssertEqual(during["keyDownCount"] as? Int, 1)
        XCTAssertEqual(during["keyUpCount"] as? Int, 1)
        XCTAssertEqual(during["menuTracking"] as? Bool, true)
        try verifyConsumedEvents(during)

        try requireForeground(app, bundleIdentifier: bundleIdentifier)
        app.typeKey(.escape, modifierFlags: [])
        try await verifyMenuClosedWithoutReplay(at: snapshotPath)
    }

    @MainActor
    private func verifyMenuClosedWithoutReplay(at path: String) async throws {
        _ = try await waitForSnapshot(at: path) { $0["menuTracking"] as? Bool == false }
        try await observeNoDelayedReplay(at: path)
        let closed = try readSnapshot(path)
        try attach(closed, name: "menu-closed-without-replayed-shortcut")
        XCTAssertEqual(closed["menuTracking"] as? Bool, false)
        XCTAssertEqual(closed["keyDownCount"] as? Int, 1)
        XCTAssertEqual(closed["keyUpCount"] as? Int, 1)
        try verifyConsumedEvents(closed)
    }

    private func requireRegisteredChord(_ snapshot: [String: Any]) throws {
        guard
            snapshot["keyDownCount"] as? Int == 0,
            snapshot["keyUpCount"] as? Int == 0,
            snapshot["shortcutEnabled"] as? Bool == true,
            snapshot["shortcutKeyCode"] as? Int == 9,
            snapshot["shortcutModifiers"] as? Int == 6912
        else {
            throw NSError(
                domain: "ShortcutMenuFixture", code: 2,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "The synthetic chord must be registered and unused before native input"
                ])
        }
    }

    @MainActor
    private func requireForeground(_ app: XCUIApplication, bundleIdentifier: String) throws {
        guard
            app.state == .runningForeground,
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier == bundleIdentifier
        else {
            throw NSError(
                domain: "ShortcutMenuFixture", code: 1,
                userInfo: [
                    NSLocalizedDescriptionKey:
                        "The fixture is not frontmost; native acceptance cannot synthesize input"
                ])
        }
    }

    private func verifyConsumedEvents(_ snapshot: [String: Any]) throws {
        let trace = try XCTUnwrap(snapshot["trace"] as? [[String: Any]])
        let callbacks = trace.filter {
            ["down-callback", "up-callback"].contains($0["phase"] as? String ?? "")
        }
        XCTAssertEqual(callbacks.count, 2)
        for callback in callbacks {
            XCTAssertEqual(callback["menuTracking"] as? Bool, true)
            XCTAssertEqual(callback["isRepeat"] as? Bool, false)
            let timestamp = try XCTUnwrap(callback["timestamp"] as? Double)
            let type = try XCTUnwrap(callback["type"] as? Int)
            let expectedType =
                callback["phase"] as? String == "down-callback"
                ? NSEvent.EventType.keyDown : .keyUp
            XCTAssertEqual(type, Int(expectedType.rawValue))
            let dequeued = trace.filter {
                $0["phase"] as? String == "dequeue"
                    && $0["timestamp"] as? Double == timestamp && $0["type"] as? Int == type
            }
            XCTAssertEqual(dequeued.count, 1, "The same native event must be dequeued once")
            XCTAssertEqual(dequeued.first?["mode"] as? String, RunLoop.Mode.eventTracking.rawValue)
        }
        XCTAssertFalse(trace.contains { $0["phase"] as? String == "repost" })
        XCTAssertFalse(trace.contains { $0["phase"] as? String == "send" })
    }

    @MainActor
    private func waitForElement(_ element: XCUIElement, seconds: Int) async throws -> Bool {
        for _ in 0..<(seconds * 20) {
            if element.exists { return true }
            try await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    @MainActor
    private func observeNoDelayedReplay(at path: String) async throws {
        for _ in 0..<20 {
            let snapshot = try readSnapshot(path)
            let trace = try XCTUnwrap(snapshot["trace"] as? [[String: Any]])
            if snapshot["keyDownCount"] as? Int != 1 || snapshot["keyUpCount"] as? Int != 1
                || trace.contains(where: {
                    ["repost", "send"].contains($0["phase"] as? String ?? "")
                })
            {
                XCTFail("A consumed shortcut was replayed after menu close")
                return
            }
            try await Task.sleep(for: .milliseconds(50))
        }
    }

    /// The fixture writes its snapshot asynchronously, so wait for the expected
    /// state (or a deadline) before asserting on it.
    @MainActor
    private func waitForSnapshot(
        at path: String, seconds: Double = 3, until isReady: ([String: Any]) -> Bool
    ) async throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(seconds)
        var snapshot = (try? readSnapshot(path)) ?? [:]
        while !isReady(snapshot), Date() < deadline {
            try await Task.sleep(for: .milliseconds(50))
            snapshot = (try? readSnapshot(path)) ?? snapshot
        }
        return snapshot
    }

    private func readSnapshot(_ path: String) throws -> [String: Any] {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func attach(_ snapshot: [String: Any], name: String) throws {
        let data = try JSONSerialization.data(
            withJSONObject: snapshot, options: [.sortedKeys, .prettyPrinted])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

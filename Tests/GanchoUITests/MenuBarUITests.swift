import AppKit
import XCTest

/// The status item as a mini-panel: its menu, its badge and modifier clicks,
/// and the helper's request to open the app's menu.
final class MenuBarUITests: XCTestCase {
    private static let nonce = "menu-bar-ui-test"

    @MainActor
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = GanchoUITestApplication()
        app.launchArguments =
            [
                "-open-panel-on-launch", "-use-in-process-status-item",
                "-use-temp-durable-store", "-seed-visual-library",
                "-force-free-tier", "-isolate-ui-test-system-clipboard",
                "-suppress-storage-notice-for-ui-test", "-ui-test-paste-sink", "pasted",
                "-command-nonce", Self.nonce, "-AppleLanguages", "(en)",
                "-ui-test-defaults-suite",
                "com.johnny4young.gancho.uitests.menubar.\(UUID().uuidString)"
            ] + extra
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 5)
        return app
    }

    @MainActor
    private func statusItem(_ app: XCUIApplication) throws -> XCUIElement {
        let item = app.statusItems.firstMatch
        guard item.waitForExistence(timeout: 8), item.isHittable else {
            throw XCTSkip("status item not hittable on this display/Space")
        }
        return item
    }

    @MainActor
    private func waitForBadge(_ value: String, on item: XCUIElement) -> Bool {
        let predicate = NSPredicate(format: "value == %@", "badge:\(value)")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: item)
        return XCTWaiter().wait(for: [expectation], timeout: 6) == .completed
    }

    @MainActor
    func testMenuListsRecentsTheStackAndTheCommands() throws {
        let app = launch(["-seed-paste-stack"])
        defer { app.terminate() }
        let item = try statusItem(app)
        XCTAssertTrue(waitForBadge("stack:2", on: item), "two clips wait in the stack")

        item.click()
        XCTAssertTrue(app.menuItems["menu-bar-header"].firstMatch.waitForExistence(timeout: 3))
        for number in 1...4 {
            let row = app.menuItems["menu-bar-recent-\(number)"].firstMatch
            XCTAssertTrue(row.exists, "recent \(number)")
        }
        XCTAssertFalse(app.menuItems["menu-bar-recent-5"].firstMatch.exists, "four clips seeded")
        let masked = app.menuItems["menu-bar-recent-4"].firstMatch
        XCTAssertTrue(masked.title.hasSuffix("· masked"), "the protected image: \(masked.title)")
        XCTAssertFalse(masked.title.contains("Hidden fixture"), "never its title")

        let stack = app.menuItems["menu-bar-paste-stack"].firstMatch
        XCTAssertTrue(stack.exists)
        XCTAssertTrue(stack.title.contains("2 waiting"), stack.title)
        for command in [
            "openPanel", "library", "copyScreenText", "toggleCapture", "togglePrivateMode",
            "ignoreNextCopy", "settings", "privacyCenter", "welcome", "wrapped", "quit"
        ] {
            XCTAssertTrue(app.menuItems["menu-bar-command-\(command)"].firstMatch.exists, command)
        }
        app.typeKey(.escape, modifierFlags: [])
    }

    @MainActor
    func testOptionClicksPauseAndIgnoreTheNextCopy() throws {
        let app = launch()
        defer { app.terminate() }
        let item = try statusItem(app)
        XCTAssertTrue(waitForBadge("none", on: item), "capturing is the bare hook")

        XCUIElement.perform(withKeyModifiers: .option) { item.click() }
        XCTAssertTrue(waitForBadge("paused", on: item), "⌥-click pauses")
        XCTAssertFalse(app.menuItems["menu-bar-header"].firstMatch.exists, "and opens no menu")

        XCUIElement.perform(withKeyModifiers: .option) { item.click() }
        XCTAssertTrue(waitForBadge("none", on: item), "⌥-click again resumes")

        XCUIElement.perform(withKeyModifiers: [.option, .shift]) { item.click() }
        XCTAssertTrue(waitForBadge("ignore-next", on: item), "⌥⇧-click ignores the next copy")
    }

    /// The helper's click with another app in front: the app's menu opens,
    /// stays open, takes ⌘1 and says it closed. No icon frame is published
    /// here, so the menu opens at the pointer.
    @MainActor
    func testHelperRequestOpensTheAppsMenu() throws {
        let app = launch()
        defer { app.terminate() }
        _ = try statusItem(app)
        // In production another app is in front when the icon is clicked.
        let finder = XCUIApplication(bundleIdentifier: "com.apple.finder")
        finder.activate()
        XCTAssertTrue(finder.wait(for: .runningForeground, timeout: 5))

        let center = DistributedNotificationCenter.default()
        let opened = expectation(
            forNotification: Notification.Name(
                "com.johnny4young.gancho.menu-bar-signal.menuDidOpen"),
            object: Self.nonce, notificationCenter: center)
        center.postNotificationName(
            Notification.Name("com.johnny4young.gancho.menu-bar-signal.showMenu"),
            object: Self.nonce, userInfo: nil, options: [.deliverImmediately])
        wait(for: [opened], timeout: 5)
        // A menu popped up away from a window isn't in the app's AX tree; its
        // rows are covered by the in-process test, which builds the same menu.
        let stillOpen = expectation(
            forNotification: Notification.Name(
                "com.johnny4young.gancho.menu-bar-signal.menuDidClose"),
            object: Self.nonce, notificationCenter: center)
        stillOpen.isInverted = true
        wait(for: [stillOpen], timeout: 1)

        // ⌘1 reaches the menu although Finder is in front: it pastes the
        // first clip (into the test's sink) and closes the menu.
        let closed = expectation(
            forNotification: Notification.Name(
                "com.johnny4young.gancho.menu-bar-signal.menuDidClose"),
            object: Self.nonce, notificationCenter: center)
        finder.typeKey("1", modifierFlags: .command)
        wait(for: [closed], timeout: 5)
    }

    /// A forged request without the launch's nonce opens nothing.
    @MainActor
    func testHelperRequestWithoutTheNonceIsIgnored() throws {
        let app = launch()
        defer { app.terminate() }
        _ = try statusItem(app)
        let center = DistributedNotificationCenter.default()
        let opened = expectation(
            forNotification: Notification.Name(
                "com.johnny4young.gancho.menu-bar-signal.menuDidOpen"),
            object: nil, notificationCenter: center)
        opened.isInverted = true
        center.postNotificationName(
            Notification.Name("com.johnny4young.gancho.menu-bar-signal.showMenu"),
            object: "forged", userInfo: nil, options: [.deliverImmediately])
        wait(for: [opened], timeout: 2)
    }

    /// Sharing the screen masks the rows and names the app; Show anyway
    /// reveals them for this share only.
    @MainActor
    func testScreenShareHidesPreviewsUntilShownAnyway() throws {
        let app = launch(["-simulate-screen-share", "Zoom"])
        defer { app.terminate() }
        let show = app.buttons["screen-share-show-anyway"].firstMatch
        XCTAssertTrue(show.waitForExistence(timeout: 10), "detection runs on a 3 s tick")
        let notice = app.descendants(matching: .any)["capture-notice"].firstMatch
        let texts = notice.staticTexts.allElementsBoundByIndex.map {
            $0.label.isEmpty ? $0.value as? String ?? "" : $0.label
        }
        XCTAssertTrue(texts.contains("Zoom is sharing. Rows show kinds only."), "\(texts)")
        let rows = app.descendants(matching: .any).matching(identifier: "clip-row")
        let code = rows.matching(NSPredicate(format: "label BEGINSWITH %@", "code,")).firstMatch
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        XCTAssertTrue(code.label.contains("•••"), "masked while sharing: \(code.label)")
        if let item = try? statusItem(app) {
            XCTAssertTrue(waitForBadge("paused", on: item), "sharing pauses capture")
        }

        // The large preview would show everything, so ⌘Y does nothing yet.
        app.activate()
        _ = app.wait(for: .runningForeground, timeout: 3)
        try SynthesizedInput.requireForeground(app)
        app.typeKey("y", modifierFlags: .command)
        XCTAssertFalse(
            app.sheets["large-preview-window"].firstMatch.waitForExistence(timeout: 2),
            "no large preview while previews are hidden")

        show.click()
        let revealed = rows.matching(
            NSPredicate(format: "label BEGINSWITH %@", "code, let greeting")
        ).firstMatch
        XCTAssertTrue(revealed.waitForExistence(timeout: 5), "Show anyway reveals the rows")
        XCTAssertFalse(show.exists)
    }

    /// A share that starts while capture is paused by hand hides previews too.
    @MainActor
    func testScreenShareDuringAManualPauseStillHidesPreviews() throws {
        let app = launch(["-start-capture-paused", "-simulate-screen-share", "Zoom"])
        defer { app.terminate() }
        XCTAssertTrue(
            app.buttons["screen-share-show-anyway"].firstMatch.waitForExistence(timeout: 10),
            "the share notice wins over the paused one")
        let code = app.descendants(matching: .any).matching(identifier: "clip-row")
            .matching(NSPredicate(format: "label BEGINSWITH %@", "code,")).firstMatch
        XCTAssertTrue(code.waitForExistence(timeout: 5))
        XCTAssertTrue(code.label.contains("•••"), "masked while sharing: \(code.label)")
    }
}

import XCTest

/// An agent read you can see: a seeded grant reads three clips through the
/// same ledger row and signal `gancho mcp` uses, and the app lights the
/// menu-bar dot and shows a HUD with Revoke.
final class AgentReadsUITests: XCTestCase {
    private static let favoritesID = "FA000000-0000-4000-A000-000000000001"

    @MainActor
    private func launch(_ extra: [String] = []) -> XCUIApplication {
        continueAfterFailure = false
        let app = GanchoUITestApplication()
        app.launchArguments =
            extra + [
                "-open-panel-on-launch", "-use-in-process-status-item", "-use-temp-durable-store",
                "-seed-mcp-grants", "-seed-agent-read", "-ui-test-keep-copy-hud",
                "-force-free-tier", "-isolate-ui-test-system-clipboard",
                "-suppress-storage-notice-for-ui-test", "-ui-test-paste-sink", "copy-only",
                "-place-panel-for-ui-test", "-opaque-panel-for-ui-test", "-AppleLanguages", "(en)",
                "-telemetry-consent", "disabled", "-ui-test-defaults-suite",
                "com.johnny4young.gancho.uitests.agent-reads.\(UUID().uuidString)"
            ]
        app.launch()
        _ = app.wait(for: .runningForeground, timeout: 5)
        return app
    }

    @MainActor
    private func hud(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["agent-read-hud"].firstMatch
    }

    /// A macOS static text carries its string as the value.
    @MainActor
    private func text(of element: XCUIElement) -> String {
        (element.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? element.label
    }

    @MainActor
    private func waitForText(_ expected: String, of element: XCUIElement) -> Bool {
        let deadline = Date().addingTimeInterval(10)
        repeat {
            if element.exists, text(of: element) == expected { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        } while Date() < deadline
        return false
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
        return XCTWaiter().wait(for: [expectation], timeout: 8) == .completed
    }

    @MainActor
    func testAgentReadShowsTheHUDAndTheDot() throws {
        let app = launch()
        defer { app.terminate() }
        XCTAssertTrue(waitForText("Claude Desktop read 3 clips", of: hud(app)), text(of: hud(app)))
        let detail = app.descendants(matching: .any)["agent-read-hud-detail"].firstMatch
        XCTAssertTrue(text(of: detail).hasPrefix("Favorites · Last 7 days · "), text(of: detail))
        XCTAssertTrue(app.buttons["copy-hud-action-revoke"].exists)
        XCTAssertTrue(waitForBadge("agent-read", on: try statusItem(app)))
        try keepRender(of: "copy-hud-panel", in: app, named: "Agent read HUD")
    }

    @MainActor
    func testRevokeFromTheHUDRevokesTheGrant() throws {
        let app = launch(["-open-mcp-access-on-launch"])
        defer { app.terminate() }
        XCTAssertTrue(waitForText("Claude Desktop read 3 clips", of: hud(app)))
        let state = app.descendants(matching: .any)["mcp-client-state-claude-desktop"].firstMatch
        XCTAssertTrue(state.waitForExistence(timeout: 5))
        XCTAssertEqual(text(of: state), "Active")
        try SynthesizedInput.requireForeground(app)

        app.buttons["copy-hud-action-revoke"].firstMatch.click()
        XCTAssertTrue(waitForText("Access revoked", of: hud(app)), text(of: hud(app)))
        XCTAssertTrue(waitForText("Revoked", of: state), text(of: state))

        let row = app.descendants(matching: .any)["mcp-ledger-row"].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the read reaches an open ledger at once")
        let form = app.scrollViews.containing(.any, identifier: "mcp-ledger-row").firstMatch
        XCTAssertTrue(row.revealByScrolling(in: form))
        let label = text(of: row)
        for part in ["Claude Desktop", "search_clips", "Favorites · Last 7 days", "3 clips"] {
            XCTAssertTrue(label.contains(part), "\(part) in \(label)")
        }
        try keepRender(of: "MCP Access", in: app, named: "MCP Access ledger after revoke")
    }

    @MainActor
    func testOpeningTheMenuClearsTheDot() throws {
        let app = launch()
        defer { app.terminate() }
        let item = try statusItem(app)
        XCTAssertTrue(waitForBadge("agent-read", on: item))
        try SynthesizedInput.requireForeground(app)

        item.click()
        let header = app.menuItems["menu-bar-header"].firstMatch
        XCTAssertTrue(header.waitForExistence(timeout: 3))
        app.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForBadge("none", on: item))
    }

    @MainActor
    func testTurnedOffTheReadStaysInTheLedgerOnly() throws {
        let app = launch(["-show-agent-reads", "NO"])
        defer { app.terminate() }
        XCTAssertFalse(hud(app).waitForExistence(timeout: 6))
        XCTAssertTrue(waitForBadge("none", on: try statusItem(app)))
    }

    /// The HUD names the board, so a read while the screen is shared stays
    /// in the ledger only.
    @MainActor
    func testScreenShareKeepsTheReadInTheLedgerOnly() throws {
        let app = launch(["-simulate-screen-share", "Zoom"])
        defer { app.terminate() }
        XCTAssertFalse(hud(app).waitForExistence(timeout: 6))
    }

    @MainActor
    func testExposedBoardIsMarkedInTheLibrary() throws {
        let token = UUID().uuidString
        let app = launch(["-place-library-for-ui-test", "-command-nonce", token])
        defer { app.terminate() }
        XCTAssertTrue(app.textFields["search-field"].firstMatch.waitForExistence(timeout: 15))
        GanchoUITestCommands.post("library", token: token)
        let library = app.windows["Library"].firstMatch
        XCTAssertTrue(library.waitForExistence(timeout: 5))
        let favorites = library.descendants(matching: .any)["library-board-\(Self.favoritesID)"]
            .firstMatch
        XCTAssertTrue(favorites.waitForExistence(timeout: 5))
        try SynthesizedInput.requireForeground(app)

        favorites.click()
        let badge = library.descendants(matching: .any)["library-exposed-badge"].firstMatch
        XCTAssertTrue(badge.waitForExistence(timeout: 5))
        try keepRender(of: "Library", in: app, named: "Library exposed board")
    }

    @MainActor
    func testIntegrationsOfferTheDotToggle() throws {
        let app = try launchSettingsWindow(extraArguments: [
            "-use-temp-durable-store", "-start-capture-paused", "-appearance", "light",
            "-ui-test-defaults-suite",
            "com.johnny4young.gancho.uitests.agent-reads-settings.\(UUID().uuidString)"
        ])
        defer { app.terminate() }
        app.buttons["settings-tab-integrations"].firstMatch.click()
        let toggle = app.descendants(matching: .any)["settings-agent-reads"].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? Int, 1, "on unless turned off")
        try keepRender(of: "Settings", in: app, named: "Integrations agent reads toggle")
        try SynthesizedInput.requireForeground(app)
        toggle.click()
        XCTAssertEqual(toggle.value as? Int, 0)
    }
}

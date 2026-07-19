import XCTest

/// Least-privilege MCP management over the real macOS app and an encrypted,
/// throwaway store. Seed hooks require the temporary store, so these tests can
/// never read or mutate a developer's actual grants or clipboard history.
final class MCPAccessUITests: XCTestCase {
    @MainActor
    func testClientStatesAndLiveRevoke() throws {
        let app = try launchMCPAccess()
        defer { app.terminate() }

        XCTAssertTrue(app.staticTexts["mcp-client-name-claude-desktop"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["mcp-client-name-cursor"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["mcp-client-name-local-scripts"].firstMatch.exists)
        XCTAssertEqual(labelOrValue(of: "mcp-client-state-claude-desktop", in: app), "Active")
        XCTAssertEqual(labelOrValue(of: "mcp-client-state-cursor", in: app), "Expired")
        XCTAssertEqual(labelOrValue(of: "mcp-client-state-local-scripts", in: app), "Revoked")
        XCTAssertEqual(labelOrValue(of: "mcp-active-client-count", in: app), "1 active")

        attach(windowScreenshot(in: app), named: "macOS MCP client grants")

        let revoke = app.buttons["mcp-revoke-client-claude-desktop"].firstMatch
        XCTAssertTrue(revoke.waitForExistence(timeout: 3))
        XCTAssertTrue(revoke.isHittable)
        revoke.click()

        XCTAssertEqual(labelOrValue(of: "mcp-client-state-claude-desktop", in: app), "Revoked")
        XCTAssertEqual(labelOrValue(of: "mcp-active-client-count", in: app), "0 active")
        XCTAssertFalse(app.buttons["mcp-copy-command-claude-desktop"].firstMatch.exists)
        attach(windowScreenshot(in: app), named: "macOS MCP live revoke")
    }

    @MainActor
    func testCreateExplicitClientGrant() throws {
        let app = try launchMCPAccess()
        defer { app.terminate() }

        let add = app.buttons["mcp-add-client-button"].firstMatch
        XCTAssertTrue(add.waitForExistence(timeout: 5))
        XCTAssertTrue(add.isEnabled)
        add.click()

        XCTAssertTrue(
            app.staticTexts["mcp-new-client-header"].firstMatch.waitForExistence(timeout: 3))
        let name = app.textFields["mcp-new-client-name-field"].firstMatch
        XCTAssertTrue(name.waitForExistence(timeout: 3))
        name.click()
        name.typeText("Raycast")

        let create = app.buttons["mcp-create-grant-button"].firstMatch
        XCTAssertTrue(create.waitForExistence(timeout: 3))
        XCTAssertTrue(create.isEnabled)
        create.click()

        XCTAssertTrue(
            app.staticTexts["mcp-client-name-raycast"].firstMatch.waitForExistence(timeout: 3))
        XCTAssertEqual(labelOrValue(of: "mcp-client-state-raycast", in: app), "Active")
        XCTAssertEqual(labelOrValue(of: "mcp-active-client-count", in: app), "2 active")
    }

    @MainActor
    private func launchMCPAccess() throws -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "-regular-activation-for-ui-tests", "-use-in-process-status-item",
            "-use-temp-durable-store",
            "-force-capture-active",
            "-disable-screen-share-auto-pause",
            "-force-pasteboard-access-allowed",
            "-seed-mcp-grants",
            "-open-mcp-access-on-launch",
            "-has-seen-welcome", "YES",
            "-AppleLanguages", "(en)"
        ]
        app.launch()
        app.activate()
        guard app.wait(for: .runningForeground, timeout: 5) else {
            XCTFail("Gancho did not reach the foreground")
            app.terminate()
            throw CocoaError(.fileNoSuchFile)
        }
        guard app.windows["MCP Access"].firstMatch.waitForExistence(timeout: 5) else {
            XCTFail("MCP Access window was not exposed to the UI runner")
            app.terminate()
            throw CocoaError(.fileNoSuchFile)
        }
        XCTAssertTrue(app.staticTexts["mcp-access-header"].firstMatch.waitForExistence(timeout: 3))
        return app
    }

    @MainActor
    private func labelOrValue(of identifier: String, in app: XCUIApplication) -> String {
        let element = app.descendants(matching: .any)[identifier].firstMatch
        XCTAssertTrue(element.waitForExistence(timeout: 5), "Missing element: \(identifier)")
        return (element.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? element.label
    }

    @MainActor
    private func windowScreenshot(in app: XCUIApplication) -> XCUIScreenshot {
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 5))
        let window = app.windows["MCP Access"].firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 3))
        return window.screenshot()
    }

    private func attach(_ screenshot: XCUIScreenshot, named name: String) {
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}

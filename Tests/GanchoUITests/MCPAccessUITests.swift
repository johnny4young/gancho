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
        XCTAssertTrue(
            waitForLabelOrValue("Active", of: "mcp-client-state-claude-desktop", in: app))
        XCTAssertTrue(waitForLabelOrValue("Expired", of: "mcp-client-state-cursor", in: app))
        XCTAssertTrue(
            waitForLabelOrValue("Revoked", of: "mcp-client-state-local-scripts", in: app))
        XCTAssertTrue(waitForLabelOrValue("1 active", of: "mcp-active-client-count", in: app))

        attach(windowScreenshot(in: app), named: "macOS MCP client grants")

        let revoke = app.buttons["mcp-revoke-client-claude-desktop"].firstMatch
        XCTAssertTrue(revoke.waitForExistence(timeout: 3))

        XCTAssertTrue(
            revokeGrant(
                with: revoke, stateIdentifier: "mcp-client-state-claude-desktop", in: app),
            "the grant state did not publish its live revocation")
        XCTAssertTrue(
            waitForLabelOrValue("0 active", of: "mcp-active-client-count", in: app),
            "the active-client summary did not converge after revocation")
        XCTAssertTrue(
            waitForNonexistence(
                app.buttons["mcp-copy-command-claude-desktop"].firstMatch, timeout: 5),
            "the active-only copy command remained exposed after revocation")
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
        XCTAssertTrue(waitForLabelOrValue("Active", of: "mcp-client-state-raycast", in: app))
        XCTAssertTrue(waitForLabelOrValue("2 active", of: "mcp-active-client-count", in: app))
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
    private func revokeGrant(
        with button: XCUIElement, stateIdentifier: String, in app: XCUIApplication
    ) -> Bool {
        // A macOS system dialog can transiently intercept a synthesized click
        // after XCTest has already reported the app button as hittable. Retry
        // only while the seeded grant is still active; the observed state
        // transition remains the proof that the action was delivered.
        for _ in 0..<3 {
            if waitForLabelOrValue("Revoked", of: stateIdentifier, in: app, timeout: 1) {
                return true
            }
            app.activate()
            guard button.waitForHittable(timeout: 3) else { continue }
            button.click()
            if waitForLabelOrValue("Revoked", of: stateIdentifier, in: app, timeout: 3) {
                return true
            }
        }
        return waitForLabelOrValue("Revoked", of: stateIdentifier, in: app, timeout: 5)
    }

    @MainActor
    private func waitForLabelOrValue(
        _ expected: String, of identifier: String, in app: XCUIApplication,
        timeout: TimeInterval = 5
    ) -> Bool {
        let element = app.descendants(matching: .any)[identifier].firstMatch
        guard element.waitForExistence(timeout: timeout) else { return false }
        let predicate = NSPredicate { object, _ in
            guard let element = object as? XCUIElement else { return false }
            return (element.value as? String).flatMap { $0.isEmpty ? nil : $0 } == expected
                || element.label == expected
        }
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    private func waitForNonexistence(
        _ element: XCUIElement, timeout: TimeInterval
    ) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
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

extension XCUIElement {
    @MainActor
    fileprivate func waitForHittable(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == true AND hittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }
}

import AppKit
import ApplicationServices
import XCTest

/// These tests intentionally use the real session clipboard and keyboard.
/// The dedicated scheme fails closed outside a disposable hosted runner.
final class SignedHandoffUITests: XCTestCase {
    private let bundleID = "com.johnny4young.gancho"
    private let receiverID = "com.johnny4young.gancho.validation.paste-receiver"

    override func setUpWithError() throws {
        try super.setUpWithError()
        try require(
            ProcessInfo.processInfo.environment["GANCHO_DISPOSABLE_SIGNED_HOST"] == "github-hosted"
                && NSUserName() == "runner",
            "Real handoff tests require a disposable GitHub-hosted runner")
        try require(AXIsProcessTrusted(), "The test driver must have real Accessibility permission")
    }

    @MainActor
    func testSignedHelperStaysResidentAndRoutesSettingsAcrossTwoLaunches() throws {
        let app = makeApp()
        defer { if app.state != .notRunning { app.terminate() } }
        for _ in 0..<2 {
            try require(noGanchoProcesses(), "The disposable host must start without Gancho")
            app.launch()
            let owner = try ownedMainApplication()
            let helper = try waitForHelper(owner: owner)
            XCTAssertEqual(owner.activationPolicy, .accessory)
            try pressHelperCommand("settings", helper: helper)
            let root = AXUIElementCreateApplication(owner.processIdentifier)
            let settings = try waitForElement(
                root, attribute: kAXTitleAttribute, value: "Settings",
                message: "The helper must open Settings in its exact owner process")
            let close = try relatedElement(settings, attribute: kAXCloseButtonAttribute)
            try require(
                AXUIElementPerformAction(close, kAXPressAction as CFString) == .success,
                "Settings must close through its native close button")
            XCTAssertTrue(
                waitUntil {
                    findElement(root, attribute: kAXTitleAttribute, value: "Settings") == nil
                })
            RunLoop.current.run(until: Date().addingTimeInterval(2))
            XCTAssertFalse(owner.isTerminated, "Closing Settings must keep the owner resident")
            XCTAssertFalse(
                helper.isTerminated, "Closing Settings must keep the signed helper resident")
            app.terminate()
            XCTAssertTrue(
                waitUntil { helper.isTerminated }, "A clean quit must stop the exact helper")
        }
    }

    @MainActor
    func testSignedHelperExitsWhenItsExactOwnerIsKilled() throws {
        try require(noGanchoProcesses(), "The disposable host must start without Gancho")
        let app = makeApp()
        app.launch()
        defer { if app.state != .notRunning { app.terminate() } }
        let owner = try ownedMainApplication()
        let helper = try waitForHelper(owner: owner)
        XCTAssertTrue(owner.forceTerminate())
        XCTAssertTrue(waitUntil { owner.isTerminated })
        XCTAssertTrue(
            waitUntil { helper.isTerminated },
            "The signed helper watchdog must stop without its owner")
        app.launch()
        let restartedOwner = try ownedMainApplication()
        let restartedHelper = try waitForHelper(owner: restartedOwner)
        XCTAssertNotEqual(restartedOwner.processIdentifier, owner.processIdentifier)
        XCTAssertNotEqual(restartedHelper.processIdentifier, helper.processIdentifier)
        app.terminate()
        XCTAssertTrue(waitUntil { restartedHelper.isTerminated })
    }

    @MainActor
    func testReturnDeliversExactlyOnceIntoAnotherApplication() throws {
        try verifyPaste(usingReturn: true)
    }

    @MainActor
    func testDoubleClickDeliversExactlyOnceIntoAnotherApplication() throws {
        try verifyPaste(usingReturn: false)
    }

    @MainActor
    private func verifyPaste(usingReturn: Bool) throws {
        try require(noGanchoProcesses(), "The disposable host must start without Gancho")
        let (receiver, editor) = try launchReceiver()
        defer { receiver.terminate() }

        let app = makeApp()
        app.launchArguments.append("-seed-sample-clips")
        app.launch()
        defer {
            if app.state != .notRunning { app.terminate() }
            XCTAssertTrue(
                waitUntil { noGanchoProcesses() },
                "Test processes must finish before the next session")
        }
        let owner = try ownedMainApplication()
        let helper = try waitForHelper(owner: owner)
        receiver.activate()
        editor.click()
        try require(
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier == receiverID,
            "The receiving application must own foreground focus before opening the panel")
        try pressHelperCommand("openPanel", helper: helper)
        let root = AXUIElementCreateApplication(owner.processIdentifier)
        let panel = try waitForElement(
            root, value: "history-panel",
            message: "The helper must open the real panel in its exact owner process")
        let search = try waitForElement(
            panel, value: "search-field",
            message: "The panel must expose its search field")
        try require(
            waitUntil { elements(in: panel, identifier: "clip-row").count == 3 },
            "All three synthetic captures must be ready")
        try require(
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier == receiverID,
            "The nonactivating panel must preserve the receiving application as paste target")

        if usingReturn {
            try require(
                waitUntil { isFocused(search) },
                "Return must be sent only after the panel search owns keyboard focus")
            try postReturn()
        } else {
            let row = try XCTUnwrap(elements(in: panel, identifier: "clip-row").first)
            try clickElement(row, clickCount: 2)
        }
        XCTAssertTrue(
            waitUntil {
                findElement(root, attribute: kAXIdentifierAttribute, value: "history-panel") == nil
            },
            "The panel must hide after paste")
        let receipt = receiver.staticTexts["paste-receipt-status"].firstMatch
        let expected = "pastes=1;down=1;up=1;match=true;marked=true"
        try require(
            waitUntil(timeout: 10) { receipt.value as? String == expected },
            "The real receiver must report one matching, marked paste and one command down/up pair")
        RunLoop.current.run(until: Date().addingTimeInterval(2))
        XCTAssertTrue(
            receipt.value as? String == expected, "No delayed or duplicate paste may arrive")
        XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.bundleIdentifier, receiverID)
        XCTAssertFalse(helper.isTerminated, "Paste must keep the external helper resident")
    }

    @MainActor
    private func launchReceiver() throws -> (XCUIApplication, XCUIElement) {
        let receiverPath = try XCTUnwrap(
            ProcessInfo.processInfo.environment["GANCHO_PASTE_RECEIVER_APP"])
        let receiver = XCUIApplication(url: URL(fileURLWithPath: receiverPath))
        receiver.launchEnvironment["GANCHO_DISPOSABLE_PASTE_RECEIVER"] = "1"
        receiver.launch()
        let editor = receiver.textViews["paste-receiver-editor"].firstMatch
        try require(editor.waitForExistence(timeout: 5), "The synthetic receiver must be ready")
        try require(editor.isHittable, "The receiver editor must be reachable")
        editor.click()
        return (receiver, editor)
    }

    @MainActor
    private func makeApp() -> GanchoUITestApplication {
        let app = GanchoUITestApplication()
        app.launchArguments = [
            "-force-ephemeral-store", "-start-capture-paused", "-has-seen-welcome", "YES",
            "-telemetry-consent", "disabled", "-suppress-storage-notice-for-ui-test"
        ]
        return app
    }

    @MainActor
    private func ownedMainApplication() throws -> NSRunningApplication {
        let expected = try XCTUnwrap(ProcessInfo.processInfo.environment["GANCHO_SIGNED_APP"])
        return try XCTUnwrap(
            NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first {
                $0.executableURL?.lastPathComponent == "Gancho"
                    && $0.bundleURL?.standardizedFileURL
                        == URL(fileURLWithPath: expected).standardizedFileURL
            })
    }

    @MainActor
    private func noGanchoProcesses() -> Bool {
        !NSWorkspace.shared.runningApplications.contains {
            $0.bundleIdentifier == bundleID
                || $0.executableURL?.lastPathComponent == "GanchoMenuBarHelper"
        }
    }

    @MainActor
    private func waitForHelper(owner: NSRunningApplication) throws -> NSRunningApplication {
        let expected = try XCTUnwrap(owner.executableURL).deletingLastPathComponent()
            .appendingPathComponent("GanchoMenuBarHelper").standardizedFileURL
        var helper: NSRunningApplication?
        try require(
            waitUntil {
                helper = NSWorkspace.shared.runningApplications.first {
                    $0.executableURL?.standardizedFileURL == expected
                }
                return helper != nil
            }, "The signed helper must run from the exact app under test")
        return try XCTUnwrap(helper)
    }

    @MainActor
    private func pressHelperCommand(_ command: String, helper: NSRunningApplication) throws {
        let root = AXUIElementCreateApplication(helper.processIdentifier)
        var status: AXUIElement?
        try require(
            waitUntil {
                status = findElement(root, attribute: kAXRoleAttribute, value: kAXMenuBarItemRole)
                return status != nil
            }, "The exact helper must expose its status item")
        try clickElement(try XCTUnwrap(status))
        var item: AXUIElement?
        try require(
            waitUntil {
                item = findElement(
                    root, attribute: kAXIdentifierAttribute,
                    value: "menu-bar-command-\(command)")
                return item != nil
            }, "The real helper menu must expose the requested command")
        try require(
            AXUIElementPerformAction(try XCTUnwrap(item), kAXPressAction as CFString) == .success,
            "The helper command must perform its native action")
    }

    @MainActor
    private func findElement(
        _ element: AXUIElement, attribute: String, value: String, depth: Int = 0
    ) -> AXUIElement? {
        guard depth < 12 else { return nil }
        var found: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, attribute as CFString, &found) == .success,
            found as? String == value
        {
            return element
        }
        var elements: [AXUIElement] = []
        for relation in [
            kAXExtrasMenuBarAttribute, kAXChildrenAttribute, kAXWindowsAttribute,
            kAXMenuBarAttribute
        ] {
            var related: CFTypeRef?
            guard
                AXUIElementCopyAttributeValue(element, relation as CFString, &related) == .success,
                let related
            else { continue }
            if let children = related as? [AXUIElement] {
                elements += children
            } else if CFGetTypeID(related) == AXUIElementGetTypeID() {
                elements.append(unsafeDowncast(related, to: AXUIElement.self))
            }
        }
        for child in elements {
            if let match = findElement(child, attribute: attribute, value: value, depth: depth + 1)
            {
                return match
            }
        }
        return nil
    }

    @MainActor
    private func clickElement(_ element: AXUIElement, clickCount: Int = 1) throws {
        var position: CFTypeRef?
        var size: CFTypeRef?
        try require(
            AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position)
                == .success
                && AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size)
                    == .success,
            "The target control must expose its native position and size")
        let positionValue = try XCTUnwrap(position)
        let sizeValue = try XCTUnwrap(size)
        try require(
            CFGetTypeID(positionValue) == AXValueGetTypeID()
                && CFGetTypeID(sizeValue) == AXValueGetTypeID(),
            "The target frame must use AX values"
        )
        var origin = CGPoint.zero
        var dimensions = CGSize.zero
        try require(
            AXValueGetValue(unsafeDowncast(positionValue, to: AXValue.self), .cgPoint, &origin)
                && AXValueGetValue(
                    unsafeDowncast(sizeValue, to: AXValue.self), .cgSize, &dimensions),
            "The target frame must be readable")
        let frame = CGRect(origin: origin, size: dimensions)
        let point = CGPoint(x: frame.midX, y: frame.midY)
        try require(
            !frame.isEmpty && !frame.isInfinite
                && CGDisplayBounds(CGMainDisplayID()).contains(point),
            "The target control must be reachable on the active display")
        let source = try XCTUnwrap(CGEventSource(stateID: .hidSystemState))
        let down = try XCTUnwrap(
            CGEvent(
                mouseEventSource: source, mouseType: .leftMouseDown,
                mouseCursorPosition: point, mouseButton: .left))
        let up = try XCTUnwrap(
            CGEvent(
                mouseEventSource: source, mouseType: .leftMouseUp,
                mouseCursorPosition: point, mouseButton: .left))
        for count in 1...clickCount {
            down.setIntegerValueField(.mouseEventClickState, value: Int64(count))
            up.setIntegerValueField(.mouseEventClickState, value: Int64(count))
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
            if count < clickCount { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
        }
    }

    @MainActor
    private func waitForElement(
        _ root: AXUIElement, attribute: String = kAXIdentifierAttribute,
        value: String, message: String
    ) throws -> AXUIElement {
        var element: AXUIElement?
        try require(
            waitUntil(timeout: 10) {
                element = findElement(root, attribute: attribute, value: value)
                return element != nil
            }, message)
        return try XCTUnwrap(element)
    }

    @MainActor
    private func relatedElement(_ root: AXUIElement, attribute: String) throws -> AXUIElement {
        var result: CFTypeRef?
        try require(
            AXUIElementCopyAttributeValue(root, attribute as CFString, &result) == .success,
            "The requested native control must exist")
        let value = try XCTUnwrap(result)
        try require(
            CFGetTypeID(value) == AXUIElementGetTypeID(), "The native control must be an AX element"
        )
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    @MainActor
    private func isFocused(_ element: AXUIElement) -> Bool {
        var focused: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, kAXFocusedAttribute as CFString, &focused)
            == .success
            && focused as? Bool == true
    }

    @MainActor
    private func elements(in root: AXUIElement, identifier: String, depth: Int = 0) -> [AXUIElement]
    {
        guard depth < 20 else { return [] }
        var value: CFTypeRef?
        if AXUIElementCopyAttributeValue(root, kAXIdentifierAttribute as CFString, &value)
            == .success,
            value as? String == identifier
        {
            return [root]
        }
        var children: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(root, kAXChildrenAttribute as CFString, &children)
                == .success,
            let children = children as? [AXUIElement]
        else { return [] }
        return children.flatMap { elements(in: $0, identifier: identifier, depth: depth + 1) }
    }

    @MainActor
    private func postReturn() throws {
        let source = try XCTUnwrap(CGEventSource(stateID: .combinedSessionState))
        let down = try XCTUnwrap(
            CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: true))
        let up = try XCTUnwrap(CGEvent(keyboardEventSource: source, virtualKey: 36, keyDown: false))
        down.post(tap: .cgSessionEventTap)
        up.post(tap: .cgSessionEventTap)
    }

    @MainActor
    private func waitUntil(timeout: TimeInterval = 8, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }

    private func require(_ condition: Bool, _ message: String) throws {
        guard condition else {
            throw NSError(
                domain: "GanchoSignedIntegration", code: 1,
                userInfo: [NSLocalizedDescriptionKey: message])
        }
    }
}

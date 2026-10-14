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
    func testSignedHelperStaysResidentAndRoutesSettingsAcrossTwoLaunches() async throws {
        let app = makeApp()
        defer { if app.isRunning { app.terminate() } }
        for _ in 0..<2 {
            try require(
                waitUntil { noGanchoProcesses() }, "The disposable host must start without Gancho")
            try await app.launch()
            let owner = try ownedMainApplication(app: app)
            let helper = try waitForHelper(owner: owner)
            XCTAssertEqual(owner.activationPolicy, .accessory)
            try pressHelperCommand("settings", helper: helper)
            let root = AXUIElementCreateApplication(owner.processIdentifier)
            var settingsWindow: AXUIElement?
            try require(
                waitUntil(timeout: 10) {
                    settingsWindow = windows(in: root, titled: "Settings")?.first
                    return settingsWindow != nil
                }, "The helper must open the owner's real Settings window")
            let settings = try XCTUnwrap(settingsWindow)
            let close = try relatedElement(settings, attribute: kAXCloseButtonAttribute)
            try require(
                AXUIElementPerformAction(close, kAXPressAction as CFString) == .success,
                "Settings must close through its native close button")
            XCTAssertTrue(
                waitUntil {
                    windows(in: root, titled: "Settings")?.isEmpty == true
                })
            observeQuietPeriod()
            XCTAssertFalse(owner.isTerminated, "Closing Settings must keep the owner resident")
            XCTAssertFalse(
                helper.isTerminated, "Closing Settings must keep the signed helper resident")
            try pressHelperCommand("quit", helper: helper)
            XCTAssertTrue(
                waitUntil { owner.isTerminated }, "The real Quit command must stop its owner")
            XCTAssertTrue(
                waitUntil { helper.isTerminated }, "A clean quit must stop the exact helper")
        }
    }

    @MainActor
    func testSignedHelperExitsWhenItsExactOwnerIsKilled() async throws {
        try require(
            waitUntil { noGanchoProcesses() }, "The disposable host must start without Gancho")
        let app = makeApp()
        defer { if app.isRunning { app.terminate() } }
        try await app.launch()
        let owner = try ownedMainApplication(app: app)
        let helper = try waitForHelper(owner: owner)
        XCTAssertTrue(owner.forceTerminate())
        XCTAssertTrue(waitUntil { owner.isTerminated })
        XCTAssertTrue(
            waitUntil { helper.isTerminated },
            "The signed helper watchdog must stop without its owner")
        try await app.launch()
        let restartedOwner = try ownedMainApplication(app: app)
        let restartedHelper = try waitForHelper(owner: restartedOwner)
        XCTAssertNotEqual(restartedOwner.processIdentifier, owner.processIdentifier)
        XCTAssertNotEqual(restartedHelper.processIdentifier, helper.processIdentifier)
        try pressHelperCommand("quit", helper: restartedHelper)
        XCTAssertTrue(waitUntil { restartedOwner.isTerminated })
        XCTAssertTrue(waitUntil { restartedHelper.isTerminated })
    }

    @MainActor
    func testReturnDeliversExactlyOnceIntoAnotherApplication() async throws {
        try await verifyPaste(usingReturn: true)
    }

    @MainActor
    func testDoubleClickDeliversExactlyOnceIntoAnotherApplication() async throws {
        try await verifyPaste(usingReturn: false)
    }

}

extension SignedHandoffUITests {
    @MainActor
    private func verifyPaste(usingReturn: Bool) async throws {
        try require(
            waitUntil { noGanchoProcesses() }, "The disposable host must start without Gancho")
        let (receiver, editor, receipt) = try launchReceiver()
        defer { receiver.terminate() }

        let app = makeApp()
        app.launchArguments.append("-seed-sample-clips")
        defer {
            if app.isRunning { app.terminate() }
            XCTAssertTrue(
                waitUntil { noGanchoProcesses() },
                "Test processes must finish before the next session")
        }
        try await app.launch()
        let owner = try ownedMainApplication(app: app)
        let helper = try waitForHelper(owner: owner)
        try activateReceiver(editor: editor)
        try pressHelperCommand("openPanel", helper: helper)
        let root = AXUIElementCreateApplication(owner.processIdentifier)
        let panel = try waitForElement(
            root, value: "history-panel", inWindows: true,
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
                windowElements(in: root, identifier: "history-panel")?.isEmpty == true
            },
            "The panel must hide after paste")
        let expected = "pastes=1;down=1;up=1;match=true;marked=true"
        try require(
            waitUntil(timeout: 10) { textValue(receipt) == expected },
            "The real receiver must report one matching, marked paste and one command down/up pair")
        observeQuietPeriod()
        XCTAssertTrue(
            textValue(receipt) == expected, "No delayed or duplicate paste may arrive")
        XCTAssertEqual(NSWorkspace.shared.frontmostApplication?.bundleIdentifier, receiverID)
        XCTAssertFalse(helper.isTerminated, "Paste must keep the external helper resident")
    }

    @MainActor
    private func launchReceiver() throws -> (XCUIApplication, AXUIElement, AXUIElement) {
        let receiverPath = try XCTUnwrap(
            ProcessInfo.processInfo.environment["GANCHO_PASTE_RECEIVER_APP"])
        let receiver = XCUIApplication(url: URL(fileURLWithPath: receiverPath))
        receiver.launchEnvironment["GANCHO_DISPOSABLE_PASTE_RECEIVER"] = "1"
        receiver.launch()
        let visibleEditor = receiver.textViews["paste-receiver-editor"].firstMatch
        try require(
            visibleEditor.waitForExistence(timeout: 5), "The synthetic receiver must be ready")
        try require(visibleEditor.isHittable, "The receiver editor must be reachable")
        let running = try receiverApplication()
        let root = AXUIElementCreateApplication(running.processIdentifier)
        let editor = try waitForElement(
            root, value: "paste-receiver-editor", inWindows: true,
            message: "The exact receiver must expose its editor")
        let receipt = try waitForElement(
            root, value: "paste-receipt-status", inWindows: true,
            message: "The exact receiver must expose its receipt")
        try clickElement(editor)
        try require(
            waitUntil { isFocused(editor) }, "The actual receiver editor must own keyboard focus")
        return (receiver, editor, receipt)
    }

    @MainActor
    private func activateReceiver(editor: AXUIElement) throws {
        let nativeReceiver = try receiverApplication()
        try require(
            nativeReceiver.activate(options: []), "Native receiver activation must be accepted")
        try require(
            waitUntil {
                NSWorkspace.shared.frontmostApplication?.processIdentifier
                    == nativeReceiver.processIdentifier
            }, "The exact receiver process must become active")
        try clickElement(editor)
        try require(
            waitUntil { isFocused(editor) }, "The receiver editor must regain keyboard focus")
        try require(
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier == receiverID,
            "The receiving application must own foreground focus before opening the panel")
    }

    @MainActor
    private func receiverApplication() throws -> NSRunningApplication {
        let receiverPath = try XCTUnwrap(
            ProcessInfo.processInfo.environment["GANCHO_PASTE_RECEIVER_APP"])
        return try XCTUnwrap(
            NSRunningApplication.runningApplications(withBundleIdentifier: receiverID).first {
                $0.bundleURL?.standardizedFileURL
                    == URL(fileURLWithPath: receiverPath).standardizedFileURL
            })
    }

    @MainActor
    private func makeApp() -> SignedHandoffApplication {
        let app = SignedHandoffApplication()
        app.launchArguments = [
            "-force-ephemeral-store", "-start-capture-paused", "-has-seen-welcome", "YES",
            "-telemetry-consent", "disabled", "-suppress-storage-notice-for-ui-test"
        ]
        return app
    }

    @MainActor
    private func ownedMainApplication(app: SignedHandoffApplication) throws -> NSRunningApplication
    {
        let expected = try XCTUnwrap(ProcessInfo.processInfo.environment["GANCHO_SIGNED_APP"])
        var owner: NSRunningApplication?
        try require(
            waitUntil {
                owner = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
                    .first {
                        $0.processIdentifier == app.processIdentifier
                            && $0.executableURL?.lastPathComponent == "Gancho"
                            && $0.bundleURL?.standardizedFileURL
                                == URL(fileURLWithPath: expected).standardizedFileURL
                    }
                return owner != nil
            }, "The exact owner must finish its native accessory launch")
        return try XCTUnwrap(owner)
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
        try clickElement(try XCTUnwrap(item))
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
        var resolved: CGRect?
        try require(
            waitUntil {
                resolved = frame(of: element)
                guard let resolved, !resolved.isEmpty, !resolved.isInfinite else { return false }
                return CGDisplayBounds(CGMainDisplayID()).contains(
                    CGPoint(x: resolved.midX, y: resolved.midY))
            },
            "The target control must become reachable on the active display; frame=\(String(describing: resolved))"
        )
        let resolvedFrame = try XCTUnwrap(resolved)
        let point = CGPoint(x: resolvedFrame.midX, y: resolvedFrame.midY)
        let source = try XCTUnwrap(CGEventSource(stateID: .hidSystemState))
        let move = try XCTUnwrap(
            CGEvent(
                mouseEventSource: source, mouseType: .mouseMoved,
                mouseCursorPosition: point, mouseButton: .left))
        move.post(tap: .cghidEventTap)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
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
    private func frame(of element: AXUIElement) -> CGRect? {
        var position: CFTypeRef?
        var size: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &position)
                == .success,
            AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &size) == .success,
            let position, let size,
            CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID()
        else { return nil }
        var origin = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(position, to: AXValue.self), .cgPoint, &origin),
            AXValueGetValue(unsafeDowncast(size, to: AXValue.self), .cgSize, &dimensions)
        else { return nil }
        return CGRect(origin: origin, size: dimensions)
    }

    /// Nil when the window list cannot be read, so a read failure never proves absence.
    @MainActor
    private func windows(in root: AXUIElement, titled title: String) -> [AXUIElement]? {
        var windows: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &windows)
                == .success,
            let windows = windows as? [AXUIElement]
        else { return nil }
        return windows.filter { candidate in
            var actualTitle: CFTypeRef?
            return AXUIElementCopyAttributeValue(
                candidate, kAXTitleAttribute as CFString, &actualTitle) == .success
                && actualTitle as? String == title
        }
    }

    @MainActor
    private func windowElements(in root: AXUIElement, identifier: String) -> [AXUIElement]? {
        var windows: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(root, kAXWindowsAttribute as CFString, &windows)
                == .success,
            let windows = windows as? [AXUIElement]
        else { return nil }
        return windows.flatMap { elements(in: $0, identifier: identifier) }
    }

    @MainActor
    private func waitForElement(
        _ root: AXUIElement, value: String, inWindows: Bool = false, message: String
    ) throws -> AXUIElement {
        var element: AXUIElement?
        try require(
            waitUntil(timeout: 10) {
                element =
                    inWindows
                    ? windowElements(in: root, identifier: value)?.first
                    : findElement(root, attribute: kAXIdentifierAttribute, value: value)
                return element != nil
            }, message)
        return try XCTUnwrap(element)
    }

    @MainActor
    private func relatedElement(_ root: AXUIElement, attribute: String) throws -> AXUIElement {
        var element: AXUIElement?
        try require(
            waitUntil {
                var result: CFTypeRef?
                guard
                    AXUIElementCopyAttributeValue(root, attribute as CFString, &result) == .success,
                    let result, CFGetTypeID(result) == AXUIElementGetTypeID()
                else { return false }
                element = unsafeDowncast(result, to: AXUIElement.self)
                return true
            }, "The requested native control must become available")
        return try XCTUnwrap(element)
    }

    @MainActor
    private func textValue(_ element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &value)
                == .success
        else { return nil }
        return value as? String
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
    private func observeQuietPeriod() {
        RunLoop.current.run(until: Date().addingTimeInterval(2))
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

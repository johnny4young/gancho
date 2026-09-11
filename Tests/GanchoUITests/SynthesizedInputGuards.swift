import XCTest

/// XCUITest events are GLOBAL: synthesized keys land on whatever app/element
/// really has keyboard focus, and coordinate clicks land on whatever window
/// owns that screen point. Gancho is a menu-bar agent, so foregrounding it can
/// silently fail under the runner — and then every "fallback" keystroke or raw
/// click drives an UNRELATED app on the developer's desktop (a local run once
/// select-all-deleted and typed into another app this way). Every synthesized
/// input path in this target must pass these guards first and skip otherwise.
enum SynthesizedInput {
    /// Call before any app-level `typeText`/`typeKey` or any coordinate
    /// click. Throws `XCTSkip` — not a failure: a runner that can't
    /// foreground the agent is an environment limitation, and continuing
    /// would type into someone else's windows.
    @MainActor
    static func requireForeground(_ app: XCUIApplication) throws {
        guard app.state == .runningForeground else {
            throw XCTSkip("app under test is not frontmost — skipping synthesized input")
        }
    }

    /// True when `element` will actually receive synthesized keys. Element-
    /// scoped `typeText` checks this itself (and errors); app-scoped typing
    /// checks nothing, so callers must gate on this.
    @MainActor
    static func hasKeyboardFocus(_ element: XCUIElement) -> Bool {
        (element.value(forKey: "hasKeyboardFocus") as? Bool) ?? false
    }

    /// Waits briefly for `element` to hold keyboard focus (a click's focus
    /// grant is asynchronous for a window that just became key).
    @MainActor
    static func waitForKeyboardFocus(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if hasKeyboardFocus(element) { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return hasKeyboardFocus(element)
    }

    /// Posts macOS's alternate context-menu gesture at an element. XCUITest
    /// exposes `rightClick()` but no control-click API, so this narrow helper is
    /// the only honest way to guard responder bridges that handle left-button
    /// drag sequences without swallowing the Control modifier path.
    @MainActor
    static func controlClick(_ element: XCUIElement, in app: XCUIApplication) throws {
        try requireForeground(app)
        guard element.exists, !element.frame.isEmpty, !element.frame.isInfinite else {
            throw XCTSkip("control-click target has no usable frame on this runner")
        }
        let point = CGPoint(x: element.frame.midX, y: element.frame.midY)
        guard CGDisplayBounds(CGMainDisplayID()).contains(point) else {
            throw XCTSkip("control-click target is outside the main display")
        }
        guard
            let source = CGEventSource(stateID: .hidSystemState),
            let down = CGEvent(
                mouseEventSource: source, mouseType: .leftMouseDown,
                mouseCursorPosition: point, mouseButton: .left),
            let up = CGEvent(
                mouseEventSource: source, mouseType: .leftMouseUp,
                mouseCursorPosition: point, mouseButton: .left)
        else {
            throw XCTSkip("the runner could not synthesize a control-click")
        }
        down.flags = .maskControl
        up.flags = .maskControl
        down.post(tap: .cghidEventTap)
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        up.post(tap: .cghidEventTap)
    }
}

/// Focuses `field` and types `text` character by character, guarded end to
/// end: app frontmost, focus click, keyboard-focus grant, and a final value
/// assert so dropped characters fail here instead of corrupting the caller's
/// next assertion. Shared by every suite that fills a text field.
@MainActor
func typeTextReliably(
    _ text: String,
    into field: XCUIElement,
    in app: XCUIApplication,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    // ⌘A + delete + typing are app-LEVEL events: if Gancho isn't frontmost or
    // the field never takes focus, they land on whatever app/element actually
    // has the keyboard — select-all-deleting someone else's text. Skip (not
    // fail) when the environment can't grant us the keyboard safely.
    try SynthesizedInput.requireForeground(app)
    if field.isHittable {
        field.click()
    } else {
        // The field exists but isn't hittable (e.g. overlaid during a
        // transition). With the app verified frontmost, its center coordinate
        // is over OUR window, so the focus click is safe.
        field.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    }
    guard SynthesizedInput.waitForKeyboardFocus(field, timeout: 2) else {
        throw XCTSkip("keyboard focus not grantable to the field — skipping synthesized input")
    }

    app.typeKey("a", modifierFlags: .command)
    app.typeKey(.delete, modifierFlags: [])
    for character in text {
        app.typeText(String(character))
        RunLoop.current.run(until: Date().addingTimeInterval(0.02))
    }

    XCTAssertEqual(
        field.value as? String, text,
        "text entry must not drop characters before asserting picker state",
        file: file,
        line: line)
}

extension XCUIElement {
    /// Shared replacement for the per-file `exists == false` expectations:
    /// polls until the element leaves the hierarchy instead of asserting a
    /// single stale snapshot.
    @MainActor
    func waitForNonexistence(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == false")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Polls until the element reports itself hittable. A caller that falls
    /// back to a coordinate click when this times out must check
    /// `isCenterOnDisplay` first (see `MCPAccessUITests.revokeGrant`). The MCP
    /// revoke failures once blamed on a misreported hittable flag were a
    /// window opening partly off-screen: XCTest was right, and the fallback
    /// clicked a point clamped to the screen edge.
    @MainActor
    func waitForHittable(timeout: TimeInterval) -> Bool {
        let predicate = NSPredicate(format: "exists == true AND hittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: self)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    /// True when the element's center lies on an active display. A coordinate
    /// click aimed anywhere else is clamped to the nearest screen edge and
    /// lands on whatever sits there.
    @MainActor
    var isCenterOnDisplay: Bool {
        guard exists, !frame.isEmpty, !frame.isInfinite else { return false }
        let center = CGPoint(x: frame.midX, y: frame.midY)
        var displays = [CGDirectDisplayID](repeating: 0, count: 16)
        var displayCount: UInt32 = 0
        guard
            CGGetActiveDisplayList(UInt32(displays.count), &displays, &displayCount) == .success
        else { return false }
        return displays.prefix(Int(displayCount)).contains { display in
            CGDisplayBounds(display).contains(center)
        }
    }
}

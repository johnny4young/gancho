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

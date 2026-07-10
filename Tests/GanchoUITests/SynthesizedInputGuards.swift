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
}

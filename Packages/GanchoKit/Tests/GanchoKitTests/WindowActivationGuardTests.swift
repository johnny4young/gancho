import Foundation
import Testing

/// A menu-bar agent's `NSApp.activate()` can be refused, which leaves a window
/// behind the active app, so Mac windows open through `bringToFront()`.
@Suite("Mac windows open above the active app")
struct WindowActivationGuardTests {
    /// The panel stays out: it keeps the other app active so it can paste into it.
    @Test func windowsOpenThroughBringToFront() throws {
        let offenders = try DesignTokenGuardTests.matches(
            of: #"makeKeyAndOrderFront\("#,
            excluding: ["NSWindow+BringToFront.swift", "PanelController.swift"])
        #expect(offenders.isEmpty, "use bringToFront(): \(offenders)")
    }
}

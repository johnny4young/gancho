import AppKit
import XCTest

/// Black-box coverage for Gancho's menu-bar-only lifetime contract. The main
/// process owns clipboard history; either the helper or the in-process fallback
/// owns the active affordance. Losing that affordance must end the main process
/// instead of leaving history resident and unreachable.
final class MenuBarLifecycleUITests: XCTestCase {
    private let ganchoBundleID = "com.johnny4young.gancho"

    @MainActor
    func testPlainLaunchUsesAccessoryActivationPolicy() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-use-in-process-status-item", "-use-temp-durable-store", "-start-capture-paused",
            "-ui-test-defaults-suite", defaultsSuiteName()
        ]
        app.launch()
        defer { app.terminate() }

        waitForAppToStart(app)
        let runningApp = NSRunningApplication.runningApplications(
            withBundleIdentifier: ganchoBundleID
        ).first
        XCTAssertEqual(
            runningApp?.activationPolicy, .accessory,
            "Gancho must remain menu-bar-only and never create a Dock presence")
    }

    @MainActor
    func testAffordanceLossTerminatesTheHistoryProcess() {
        let app = XCUIApplication()
        app.launchArguments = [
            "-use-temp-durable-store", "-start-capture-paused",
            "-remove-menu-bar-affordance-after-launch", "-ui-test-defaults-suite",
            defaultsSuiteName()
        ]
        app.launch()
        defer { if app.state != .notRunning { app.terminate() } }

        waitForAppToStart(app)
        XCTAssertTrue(
            app.wait(for: .notRunning, timeout: 10),
            "losing the menu-bar icon must terminate the background history process")
        XCTAssertTrue(
            waitForGanchoMain(present: false, timeout: 2),
            "Gancho must not leave an iconless main process behind")
    }

    // MARK: - Process observation

    private func defaultsSuiteName() -> String {
        "com.johnny4young.gancho.uitests.menu-bar-lifecycle.\(UUID().uuidString)"
    }

    @MainActor
    private func waitForAppToStart(_ app: XCUIApplication) {
        let deadline = Date().addingTimeInterval(5)
        while app.state == .notRunning && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertNotEqual(app.state, .notRunning, "Gancho must finish launching")
    }

    @MainActor
    private func waitForGanchoMain(present: Bool, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let isRunning = !NSRunningApplication.runningApplications(
                withBundleIdentifier: ganchoBundleID
            ).isEmpty
            if isRunning == present { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return !NSRunningApplication.runningApplications(
            withBundleIdentifier: ganchoBundleID
        ).isEmpty == present
    }
}

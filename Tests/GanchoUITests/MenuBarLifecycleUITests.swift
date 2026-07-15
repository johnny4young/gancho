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
        ).first { $0.executableURL?.lastPathComponent == "Gancho" }
        XCTAssertEqual(
            runningApp?.activationPolicy, .accessory,
            "Gancho must remain menu-bar-only and never create a Dock presence")
    }

    @MainActor
    func testAffordanceLossTerminatesTheHistoryProcess() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-use-temp-durable-store", "-start-capture-paused",
            "-remove-menu-bar-affordance-after-launch", "-ui-test-defaults-suite",
            defaultsSuiteName()
        ]
        app.launch()
        defer { if app.state != .notRunning { app.terminate() } }

        waitForAppToStart(app)
        let mainApp = try XCTUnwrap(
            NSRunningApplication.runningApplications(
                withBundleIdentifier: ganchoBundleID
            ).first { $0.executableURL?.lastPathComponent == "Gancho" })
        XCTAssertTrue(
            waitForTermination(of: mainApp, timeout: 10),
            "Gancho must not leave an iconless main process behind")
    }

    @MainActor
    func testExternalHelperExitsAfterMainProcessIsKilled() throws {
        if ProcessInfo.processInfo.environment["GANCHO_UI_ADHOC_SIGNING"] == "1" {
            throw XCTSkip(
                "menu-bar helper launch requires Apple Development signing; CI uses entitlements-free ad-hoc signing"
            )
        }

        terminateMenuBarHelpers()
        let app = XCUIApplication()
        app.launchArguments = ["-use-temp-durable-store", "-start-capture-paused"]
        app.launch()
        defer {
            if app.state != .notRunning { app.terminate() }
            terminateMenuBarHelpers()
        }

        waitForAppToStart(app)
        XCTAssertTrue(
            waitForMenuBarHelper(present: true, timeout: 5),
            "plain launch must start the external menu-bar helper")

        let mainApp = NSRunningApplication.runningApplications(
            withBundleIdentifier: ganchoBundleID
        ).first { $0.executableURL?.lastPathComponent == "Gancho" }
        XCTAssertTrue(try XCTUnwrap(mainApp).forceTerminate())

        XCTAssertTrue(
            waitForMenuBarHelper(present: false, timeout: 5),
            "the helper watchdog must exit after its exact main process is gone")
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
    private func waitForTermination(
        of application: NSRunningApplication,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if application.isTerminated { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return application.isTerminated
    }

    @MainActor
    private func waitForMenuBarHelper(present: Bool, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let isRunning = !menuBarHelpers().isEmpty
            if isRunning == present { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return !menuBarHelpers().isEmpty == present
    }

    @MainActor
    private func terminateMenuBarHelpers() {
        for helper in menuBarHelpers() {
            _ = helper.forceTerminate()
        }
        _ = waitForMenuBarHelper(present: false, timeout: 2)
    }

    @MainActor
    private func menuBarHelpers() -> [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter {
            $0.executableURL?.lastPathComponent == "GanchoMenuBarHelper"
        }
    }
}

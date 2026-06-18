import AppKit
import ServiceManagement

/// Launches and stops the external menu-bar helper.
///
/// Prefers `SMAppService` — the sandbox-safe, launchd-managed path required for
/// an App Store build — and falls back to a direct `Process` launch when the
/// service cannot be registered (e.g. an unsigned Debug build from DerivedData).
/// Either way the helper self-exits once the main app is gone (its own bundle-id
/// watchdog), so no path leaves an orphan in the menu bar.
@MainActor
enum GanchoMenuBarHelperLauncher {
    private static let executableName = "GanchoMenuBarHelper"
    private static let agentPlistName = "com.johnny4young.gancho.menubar-helper.plist"
    private static let helperBundleID = "com.johnny4young.gancho.menubar-helper"

    @discardableResult
    static func launch() -> Bool {
        if registerService() { return true }
        return launchProcess()
    }

    static func stop() {
        unregisterService()
        terminateRunningHelpers()
    }

    // MARK: - SMAppService (sandbox-safe, preferred)

    private static var service: SMAppService {
        SMAppService.agent(plistName: agentPlistName)
    }

    private static func registerService() -> Bool {
        let service = service
        if service.status == .enabled { return true }
        do {
            try service.register()
            return service.status == .enabled
        } catch {
            // Unsigned/Debug builds can't register a LaunchAgent; fall back.
            return false
        }
    }

    private static func unregisterService() {
        guard service.status == .enabled else { return }
        service.unregister { _ in }
    }

    // MARK: - Process fallback (Debug / unsigned)

    private static func launchProcess() -> Bool {
        guard let executableURL else { return false }
        terminateRunningHelpers()

        let process = Process()
        process.executableURL = executableURL
        do {
            try process.run()
            return true
        } catch {
            return false
        }
    }

    private static var executableURL: URL? {
        guard let directory = Bundle.main.executableURL?.deletingLastPathComponent() else {
            return nil
        }
        let url = directory.appendingPathComponent(executableName, isDirectory: false)
        return FileManager.default.isExecutableFile(atPath: url.path) ? url : nil
    }

    private static func terminateRunningHelpers() {
        let currentProcessID = ProcessInfo.processInfo.processIdentifier
        for app in NSWorkspace.shared.runningApplications
        where app.processIdentifier != currentProcessID && isHelper(app) {
            _ = app.terminate()
        }
    }

    private static func isHelper(_ app: NSRunningApplication) -> Bool {
        app.bundleIdentifier == helperBundleID
            || app.executableURL?.lastPathComponent == executableName
            || app.localizedName == executableName
    }
}

import AppKit
import ServiceManagement

/// Launches and stops the external menu-bar helper.
///
/// Prefers `SMAppService` — the sandbox-safe, launchd-managed path required for
/// an App Store build — and falls back to a direct `Process` launch when the
/// service cannot be registered (e.g. an unsigned Debug build from DerivedData)
/// or when launchd won't (re)spawn it. Either way the helper self-exits once the
/// main app is gone (its owning-process watchdog), so no path leaves an orphan
/// in the menu bar.
@MainActor
enum GanchoMenuBarHelperLauncher {
    private static let executableName = "GanchoMenuBarHelper"
    private static let agentPlistName = "com.johnny4young.gancho.menubar-helper.agent.plist"
    private static let legacyAgentPlistNames = [
        "com.johnny4young.gancho.menubar-helper.plist"
    ]
    private static let helperBundleID = "com.johnny4young.gancho.menubar-helper"

    /// What `launch()` should do once SMAppService has been consulted.
    ///
    /// `SMAppService.status == .enabled` means the login agent is REGISTERED,
    /// not RUNNING. launchd runs a `RunAtLoad` agent once when it first loads it
    /// and never re-spawns it after the helper's watchdog self-exits (the plist
    /// has no `KeepAlive`). So registration is trustworthy ONLY in the moment it
    /// first loads the agent; on every later launch the helper is gone and must
    /// be ensured directly. The decision therefore keys on the process table,
    /// not on the registration flag — the bug it fixes is a signed build whose
    /// 2nd launch found the agent `.enabled` but no helper running, and so
    /// short-circuited without ever showing the menu-bar icon.
    enum LaunchPlan: Sendable, Equatable {
        /// A helper is already up (launchd just spawned it, or a leftover).
        case helperAlreadyRunning
        /// We just loaded the agent — launchd's `RunAtLoad` will spawn it.
        case trustLaunchd
        /// Already-loaded-but-dead, unsigned, or awaiting approval — spawn now.
        case launchProcess
    }

    static func launchPlan(justLoadedAgent: Bool, helperAlreadyRunning: Bool) -> LaunchPlan {
        if helperAlreadyRunning { return .helperAlreadyRunning }
        return justLoadedAgent ? .trustLaunchd : .launchProcess
    }

    @discardableResult
    static func launch() -> Bool {
        retireLegacyServices()
        let justLoaded = registerAgent()
        switch launchPlan(justLoadedAgent: justLoaded, helperAlreadyRunning: isHelperRunning()) {
        case .helperAlreadyRunning, .trustLaunchd:
            return true
        case .launchProcess:
            return launchProcess()
        }
    }

    static func stop() {
        unregisterService()
        unregisterLegacyServices()
        terminateRunningHelpers()
    }

    // MARK: - SMAppService (sandbox-safe login persistence)

    private static var service: SMAppService {
        SMAppService.agent(plistName: agentPlistName)
    }

    /// Registers the login agent if it isn't already, returning `true` ONLY when
    /// this call transitioned it to `.enabled` — i.e. launchd just loaded it and
    /// its one `RunAtLoad` spawn is imminent. An already-`.enabled` agent returns
    /// `false`: launchd loaded it earlier, its `RunAtLoad` has already fired, and
    /// a running helper must be ensured another way. A signed build awaiting the
    /// user's approval (`.requiresApproval`) also returns `false`.
    @discardableResult
    private static func registerAgent() -> Bool {
        let service = service
        guard service.status != .enabled else { return false }
        do {
            try service.register()
            return service.status == .enabled
        } catch {
            // Unsigned/Debug builds can't register a LaunchAgent; spawn directly.
            return false
        }
    }

    private static func unregisterService() {
        guard service.status == .enabled else { return }
        service.unregister { _ in }
    }

    /// Retires previously shipped service labels before loading the current
    /// helper. Service Management caches a launch constraint for each label;
    /// reusing a record after the embedded executable changes can leave a valid
    /// replacement unable to spawn. Keeping the old plist in the bundle lets
    /// upgrades unregister that job without resetting unrelated login items.
    private static func retireLegacyServices() {
        let services = legacyServices.filter { $0.status == .enabled }
        guard !services.isEmpty else { return }

        for service in services {
            try? service.unregister()
        }
        terminateRunningHelpers()
    }

    private static func unregisterLegacyServices() {
        for service in legacyServices where service.status == .enabled {
            service.unregister { _ in }
        }
    }

    private static var legacyServices: [SMAppService] {
        legacyAgentPlistNames.map { SMAppService.agent(plistName: $0) }
    }

    // MARK: - Process fallback (Debug / unsigned / re-spawn)

    private static func launchProcess() -> Bool {
        guard let executableURL else { return false }
        terminateRunningHelpers()

        let process = Process()
        process.executableURL = executableURL
        do {
            try process.run()
            return true
        } catch {
            // App Sandbox denies spawning a child process; the app then falls
            // back to its in-process status item (see GanchoAppDelegate).
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

    /// Whether a menu-bar helper other than this process is already running.
    /// Internal so the app delegate can VERIFY a launch actually produced a
    /// helper (launchd may decline to respawn, the sandbox may block the child,
    /// the helper may crash) and fall back to the in-process item if not.
    static func isHelperRunning() -> Bool {
        let currentProcessID = ProcessInfo.processInfo.processIdentifier
        return NSWorkspace.shared.runningApplications.contains {
            $0.processIdentifier != currentProcessID && isHelper($0)
        }
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

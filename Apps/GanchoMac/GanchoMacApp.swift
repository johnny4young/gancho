import AppKit
import ClipboardCore
import CoreSpotlight
import GanchoDesign
import GanchoKit
import KeyboardShortcuts
import SwiftUI

/// Menu-bar agent. The panel (⇧⌘V) is the primary surface; the status-item
/// menu is the secondary, glanceable one.
@main
struct GanchoMacApp: App {
    // Menu-bar agent lifecycle (see GanchoAppDelegate): keeps the app resident
    // when the last auxiliary window closes, instead of quitting.
    @NSApplicationDelegateAdaptor(GanchoAppDelegate.self) private var appDelegate
    @State private var model: AppModel

    init() {
        GanchoSingleInstance.terminateOlderCopies()
        let model = AppModel()
        _model = State(initialValue: model)
        GanchoRuntime.model = model
        GanchoDeepLinks.model = model
    }

    var body: some Scene {
        Settings {
            SettingsView()
                .environment(model)
                .ganchoTinted()
        }
    }
}

@MainActor
private enum GanchoRuntime {
    static var model: AppModel?
    static let statusItem = StatusItemController()
    /// Per-launch nonce used to validate helper notifications and
    /// `gancho://menu-bar/...` opens. A UI test can pin it via
    /// `-command-nonce <value>` without reading cross-process state.
    static let commandNonce: String = {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "-command-nonce"), index + 1 < arguments.count {
            return arguments[index + 1]
        }
        return UUID().uuidString
    }()
    static let menuBarPublisher = GanchoMenuBarStatusPublisher()
    static let menuBarLifecycleGuard = GanchoMenuBarLifecycleGuard()

    static var usesInProcessStatusItem: Bool {
        CommandLine.arguments.contains("-use-in-process-status-item")
    }

    static var needsRegularActivationForUITests: Bool {
        CommandLine.arguments.contains("-open-panel-on-launch")
            || CommandLine.arguments.contains("-regular-activation-for-ui-tests")
    }

    #if DEBUG
        static var removesMenuBarAffordanceForUITests: Bool {
            CommandLine.arguments.contains("-remove-menu-bar-affordance-after-launch")
        }

        static var deepLinkForUITests: URL? {
            let arguments = CommandLine.arguments
            guard let index = arguments.firstIndex(of: "-open-deep-link-on-launch"),
                index + 1 < arguments.count
            else { return nil }
            return URL(string: arguments[index + 1])
        }
    #endif
}

@MainActor
private enum GanchoSingleInstance {
    static func terminateOlderCopies() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }

        let currentProcessID = ProcessInfo.processInfo.processIdentifier
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        where app.processIdentifier != currentProcessID {
            if app.terminate() {
                waitForTermination(of: app, timeout: 1)
            }

            if !app.isTerminated {
                app.forceTerminate()
                waitForTermination(of: app, timeout: 0.5)
            }
        }
    }

    private static func waitForTermination(of app: NSRunningApplication, timeout: TimeInterval) {
        let deadline = Date().addingTimeInterval(timeout)
        while !app.isTerminated && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }
}

/// A menu-bar agent must outlive its windows. By default AppKit calls
/// `terminate:` once the last window closes (and an idle, window-less agent is
/// also eligible for Automatic Termination) — so opening then closing Settings,
/// onboarding, the Library, or even a transient launch window would quit
/// Gancho and drop it out of the menu bar. Returning `false` keeps the agent
/// resident; only the explicit "Quit Gancho" command (or ⌘Q) ends it.
@MainActor
final class GanchoAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Re-assert the launch-time policy after SwiftUI finishes scene bring-up.
        // Gancho is intentionally menu-bar-only; regular activation remains a
        // narrow UI-test hook so XCUITest can drive its otherwise-agent windows.
        NSApp.setActivationPolicy(
            GanchoRuntime.needsRegularActivationForUITests
                ? .regular : .accessory)

        // Apply the saved appearance override (Auto = follow the system). AppModel
        // also re-applies this when the user changes it in Settings.
        let savedAppearance =
            AppearancePreference(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "")
            ?? .auto
        NSApp.appearance = savedAppearance.nsAppearance

        // Belt-and-suspenders for the window-less case: a resident agent should
        // not be reclaimed by Automatic Termination while it sits in the menu bar.
        ProcessInfo.processInfo.disableAutomaticTermination(
            "Gancho runs as a resident menu-bar agent")

        // CKSyncEngine delivers remote changes over APNs push and observes them
        // itself — but only if the process is registered with APNs. A window app
        // gets registered through the normal activation path; a menu-bar AGENT
        // (`.accessory`, no key window) does not, so it must ask explicitly or it
        // never hears about clips copied on other devices and inbound sync only
        // catches up on a manual cycle. AppKit's guidance is to register at
        // launch; the push entitlement authorizes it, this activates it. Free /
        // signed-out users simply get a benign failure (logged content-free).
        NSApp.registerForRemoteNotifications()

        // Publish the initial content-free command/status state BEFORE the
        // helper paints: the command nonce (#5), localized menu titles (#4),
        // and current status presentation (#3). No clip-derived value is
        // written during this startup step.
        if let model = GanchoRuntime.model {
            GanchoMenuBarBridge.writeNonce(GanchoRuntime.commandNonce)
            GanchoRuntime.menuBarPublisher.start(model: model)
        }

        startMenuBarCommandChannel()
        establishMenuBarPresence()

        #if DEBUG
            if let deepLink = GanchoRuntime.deepLinkForUITests {
                Task { @MainActor in
                    // Exercise the production handler after AppKit has finished
                    // wiring the test process, without asking the hardened UI
                    // runner to send a TCC-protected Apple Event.
                    try? await Task.sleep(for: .milliseconds(300))
                    GanchoDeepLinks.open(deepLink)
                }
            }
        #endif
    }

    private func startMenuBarCommandChannel() {
        let center = DistributedNotificationCenter.default()
        for command in GanchoMenuBarCommand.allCases {
            center.addObserver(
                self,
                selector: #selector(receiveMenuBarCommand(_:)),
                name: command.distributedNotificationName,
                object: nil,
                suspensionBehavior: .deliverImmediately)
        }
    }

    @objc private func receiveMenuBarCommand(_ notification: Notification) {
        guard
            let command = GanchoMenuBarCommand.command(
                forDistributedNotification: notification.name),
            let token = notification.object as? String,
            token == GanchoRuntime.commandNonce,
            let model = GanchoRuntime.model
        else { return }

        command.perform(on: model)
        GanchoRuntime.menuBarPublisher.publishNow()
    }

    /// Establishes the menu-bar affordance that owns the background lifetime.
    ///
    /// The external helper spawns asynchronously (launchd `RunAtLoad` or a direct
    /// `Process`), and either can silently fail — launchd declines to respawn a
    /// self-exited agent, the sandbox blocks the child, or the helper crashes. So
    /// we do not trust `launch()`'s return: we VERIFY the helper actually appears
    /// in the process table shortly after, and if it never does, attach the
    /// in-process `NSStatusItem` fallback. Once an owner is confirmed, the
    /// lifecycle guard watches it continuously and terminates Gancho if the
    /// affordance disappears; clipboard history can never remain resident and
    /// unreachable in the background.
    private func establishMenuBarPresence() {
        guard let model = GanchoRuntime.model else { return }
        if GanchoRuntime.usesInProcessStatusItem {
            monitorInProcessStatusItem(model: model)
            return
        }

        GanchoMenuBarHelperLauncher.launch()

        Task { @MainActor in
            // Poll briefly for the helper (a local Developer ID spawn appears in
            // well under a second; give launchd's RunAtLoad generous headroom).
            for _ in 0..<14 {
                if GanchoMenuBarHelperLauncher.isHelperRunning() {
                    // The helper owns the icon — never paint a duplicate.
                    monitorExternalHelper()
                    return
                }
                try? await Task.sleep(for: .milliseconds(150))
            }
            // The helper may have appeared on the final interval — re-check once
            // more so a slightly-slow spawn isn't reported as a failure.
            if GanchoMenuBarHelperLauncher.isHelperRunning() {
                monitorExternalHelper()
                return
            }
            // The helper never came up: fall back to the AppKit-owned item so the
            // menu bar is never silently empty. Do not re-attach or re-log if a
            // duplicate launch callback arrives (the DiagnosticLog is capped).
            guard !GanchoRuntime.statusItem.isAttached else { return }
            model.diagnostics.record(
                String(localized: "Menu bar"),
                String(localized: "The menu-bar helper didn’t start; using the built-in icon."))
            monitorInProcessStatusItem(model: model)
        }
    }

    private func monitorExternalHelper() {
        GanchoRuntime.statusItem.detach()
        GanchoRuntime.menuBarLifecycleGuard.monitorExternalHelper()
        #if DEBUG
            scheduleAffordanceRemovalForUITests {
                GanchoMenuBarHelperLauncher.stop()
            }
        #endif
    }

    private func monitorInProcessStatusItem(model: AppModel) {
        GanchoRuntime.statusItem.attach(model: model)
        GanchoRuntime.menuBarLifecycleGuard.monitorInProcessStatusItem(GanchoRuntime.statusItem)
        #if DEBUG
            scheduleAffordanceRemovalForUITests {
                GanchoRuntime.statusItem.detach()
            }
        #endif
    }

    #if DEBUG
        /// Gives the UI harness a deterministic way to remove whichever
        /// production affordance won launch without exposing a user-facing
        /// command that could strand clipboard history accidentally.
        private func scheduleAffordanceRemovalForUITests(
            _ removeAffordance: @escaping @MainActor () -> Void
        ) {
            guard GanchoRuntime.removesMenuBarAffordanceForUITests else { return }
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(4))
                removeAffordance()
            }
        }
    #endif

    func applicationWillTerminate(_ notification: Notification) {
        DistributedNotificationCenter.default().removeObserver(self)
        GanchoRuntime.menuBarLifecycleGuard.stop()
        GanchoMenuBarHelperLauncher.stop()
    }

    // CKSyncEngine subscribes to and consumes CloudKit's change pushes on its
    // own — the app only needs to BE registered (hold a device token), never to
    // forward the payload — so the success callback has nothing to do.
    func application(
        _ application: NSApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {}

    func application(
        _ application: NSApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        // Without push, inbound sync degrades to manual catch-up (panel open,
        // wake) — surface it content-free so it's diagnosable, never fatal.
        GanchoRuntime.model?.diagnostics.record(
            String(localized: "Sync"),
            String(
                localized:
                    "Couldn’t subscribe to iCloud change notifications; inbound sync may lag."))
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(GanchoDeepLinks.open)
    }

    /// A curated snippet opened from Spotlight brings the history panel up —
    /// the donation's identifier is the clip id, so row-level reveal can layer
    /// on later without re-donating anything.
    func application(
        _ application: NSApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([any NSUserActivityRestoring]) -> Void
    ) -> Bool {
        guard userActivity.activityType == CSSearchableItemActionType,
            let model = GanchoRuntime.model
        else { return false }
        NSApp.activate(ignoringOtherApps: true)
        model.panel.show(model: model)
        return true
    }
}

@MainActor
private enum GanchoDeepLinks {
    static weak var model: AppModel?

    static func open(_ url: URL) {
        guard url.scheme == "gancho" else { return }

        if let command = GanchoMenuBarCommand(deepLink: url) {
            // Honor a menu-bar command only when it carries this launch's nonce,
            // so a forged gancho://menu-bar/... open from another app is ignored.
            guard let model,
                let token = GanchoMenuBarCommand.token(in: url),
                token == GanchoRuntime.commandNonce
            else { return }
            command.perform(on: model)
            GanchoRuntime.menuBarPublisher.publishNow()
            return
        }

        switch url.host?.lowercased() {
        case "settings":
            guard let model else { return }
            model.settingsWindow.show(model: model)
        case "panel":
            guard let model else { return }
            model.panel.show(model: model)
        default:
            return
        }
    }
}

/// Publishes the content-free menu-bar state to the App Group bridge so the
/// external helper renders a localized, status-aware menu without ever touching
/// clipboard data. `monitor.status` is an engine value (not `@Observable`), so a
/// light 1s poll keeps the bridge fresh and user-driven changes also publish
/// immediately. Runs on both launch paths (helper and in-process fallback).
@MainActor
final class GanchoMenuBarStatusPublisher {
    private weak var model: AppModel?
    private var timer: Timer?
    private var lastStatus: MonitorStatus?

    func start(model: AppModel) {
        self.model = model
        publishTitles()
        publishNow()
        timer?.invalidate()
        timer = Timer.scheduledTimer(
            timeInterval: 1, target: self, selector: #selector(publishNow), userInfo: nil,
            repeats: true)
    }

    private func publishTitles() {
        var titles: [String: String] = [:]
        for command in GanchoMenuBarCommand.allCases {
            titles[command.rawValue] = command.helperTitle
        }
        GanchoMenuBarBridge.writeTitles(titles)
    }

    @objc func publishNow() {
        guard let model, model.monitorStatus != lastStatus else { return }
        lastStatus = model.monitorStatus
        let presentation = StatusItemPresentation(status: model.monitorStatus)
        GanchoMenuBarBridge.writeStatus(
            icon: presentation.icon,
            label: presentation.accessibilityDescription)
    }
}

import AppKit
import ClipboardCore
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
    /// Per-launch nonce stamped onto helper command deep links so forged
    /// `gancho://menu-bar/...` opens from other processes are rejected. A UI
    /// test can pin it via `-command-nonce <value>` to drive a deterministic
    /// deep link without reading cross-process state.
    static let commandNonce: String = {
        let arguments = CommandLine.arguments
        if let index = arguments.firstIndex(of: "-command-nonce"), index + 1 < arguments.count {
            return arguments[index + 1]
        }
        return UUID().uuidString
    }()
    static let menuBarPublisher = GanchoMenuBarStatusPublisher()

    static var usesInProcessStatusItem: Bool {
        CommandLine.arguments.contains("-use-in-process-status-item")
    }

    static var needsRegularActivationForUITests: Bool {
        CommandLine.arguments.contains("-open-panel-on-launch")
    }
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
        // AppModel also applies this when the user toggles Show in Dock.
        NSApp.setActivationPolicy(
            GanchoRuntime.needsRegularActivationForUITests
                || UserDefaults.standard.bool(forKey: "show-in-dock")
                ? .regular : .accessory)

        // Belt-and-suspenders for the window-less case: a resident agent should
        // not be reclaimed by Automatic Termination while it sits in the menu bar.
        ProcessInfo.processInfo.disableAutomaticTermination(
            "Gancho runs as a resident menu-bar agent")

        // Publish the content-free side channel BEFORE the helper paints: the
        // command nonce (#5), the localized menu titles (#4), and the current
        // status presentation (#3). No clipboard data ever crosses it.
        if let model = GanchoRuntime.model {
            GanchoMenuBarBridge.writeNonce(GanchoRuntime.commandNonce)
            GanchoRuntime.menuBarPublisher.start(model: model)
        }

        let launchedHelper =
            GanchoRuntime.usesInProcessStatusItem
            ? false
            : GanchoMenuBarHelperLauncher.launch()

        if !launchedHelper, let model = GanchoRuntime.model {
            GanchoRuntime.statusItem.attach(model: model)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        GanchoMenuBarHelperLauncher.stop()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(GanchoDeepLinks.open)
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

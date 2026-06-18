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
    private let statusItem = StatusItemController()

    init() {
        GanchoSingleInstance.terminateOlderCopies()
        let model = AppModel()
        _model = State(initialValue: model)
        GanchoDeepLinks.model = model
        statusItem.attach(model: model)
    }

    var body: some Scene {
        Settings {
            SettingsView()
                .environment(model)
        }
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
        // Belt-and-suspenders for the window-less case: a resident agent should
        // not be reclaimed by Automatic Termination while it sits in the menu bar.
        ProcessInfo.processInfo.disableAutomaticTermination(
            "Gancho runs as a resident menu-bar agent")
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

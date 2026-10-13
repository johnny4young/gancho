import AppKit
import KeyboardShortcuts
import Observation
import SwiftUI

/// The real dependency recorder with synthetic preferences and inert handlers.
/// Gancho's application, capture, helper, and purchase lifecycles never start.
@Observable
@MainActor
final class RecorderFixtureState {
    var panelDown = 0 { didSet { writeSnapshot() } }
    var panelUp = 0 { didSet { writeSnapshot() } }
    var cyclicDown = 0 { didSet { writeSnapshot() } }
    var cyclicUp = 0 { didSet { writeSnapshot() } }
    var changes = 0 { didSet { writeSnapshot() } }
    var recordingActive = false { didSet { writeSnapshot() } }
    var shortcutWarning: String?
    let snapshotURL: URL
    let identifier: String
    let seededValues: String
    var displayedRecorders: () -> [String: String] = { [:] }
    var boundMenuShortcut: () -> (key: String, modifiers: UInt) = { ("", 0) }
    private var recordingObserver: NSObjectProtocol?

    init() {
        let arguments = CommandLine.arguments
        let prefix = "com.johnny4young.gancho.tests.shortcut-recorder."
        guard let identifier = Bundle.main.bundleIdentifier,
            identifier.hasPrefix(prefix),
            identifier.dropFirst(prefix.count).count == 32,
            identifier.dropFirst(prefix.count).allSatisfy({ "0123456789abcdef".contains($0) }),
            let index = arguments.firstIndex(of: "-fixture-snapshot"),
            arguments.indices.contains(index + 1)
        else { fatalError("An isolated recorder identity and snapshot are required") }
        self.identifier = identifier
        snapshotURL = URL(fileURLWithPath: arguments[index + 1]).standardizedFileURL
        let rootName = snapshotURL.deletingLastPathComponent().lastPathComponent
        guard snapshotURL.lastPathComponent == "recorder-snapshot.json",
            rootName.hasPrefix("gancho-shortcut-menu.")
                || rootName.hasPrefix("gancho-shortcut-recorder.")
        else { fatalError("Snapshot must belong to the disposable fixture directory") }

        if arguments.contains("-fixture-seed") {
            // Seed storage before accessing a Name: its initializer may install
            // a default, so using setShortcut here would not prove restoration.
            UserDefaults.standard.removePersistentDomain(forName: identifier)
            UserDefaults.standard.setPersistentDomain(
                [
                    "KeyboardShortcuts_toggle-panel":
                        #"{"carbonKeyCode":9,"carbonModifiers":6912}"#,
                    "KeyboardShortcuts_cyclic-paste":
                        #"{"carbonKeyCode":40,"carbonModifiers":6912}"#,
                    "KeyboardShortcuts_copy-screen-text":
                        #"{"carbonKeyCode":17,"carbonModifiers":6912}"#
                ], forName: identifier)
            UserDefaults.standard.synchronize()
        }
        seededValues = Self.storedValues(identifier: identifier)

        KeyboardShortcuts.onKeyDown(for: .togglePanel) { [weak self] in
            self?.panelDown += 1
        }
        KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak self] in
            self?.panelUp += 1
        }
        KeyboardShortcuts.onKeyDown(for: .cyclicPaste) { [weak self] in
            self?.cyclicDown += 1
        }
        KeyboardShortcuts.onKeyUp(for: .cyclicPaste) { [weak self] in
            self?.cyclicUp += 1
        }
        // A notification emitted by the actual native recorder; no simulated
        // recording state or dependency-source modification is involved.
        recordingObserver = NotificationCenter.default.addObserver(
            forName: Notification.Name("KeyboardShortcuts_recorderActiveStatusDidChange"),
            object: nil, queue: .main
        ) { [weak self] notification in
            let active = notification.userInfo?["isActive"] as? Bool ?? false
            Task { @MainActor [weak self] in self?.recordingActive = active }
        }
        writeSnapshot()
    }

    private static func storedValues(identifier: String) -> String {
        let values = (UserDefaults.standard.persistentDomain(forName: identifier) ?? [:])
            .filter { $0.key.hasPrefix("KeyboardShortcuts_") }
        guard
            let data = try? JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]),
            let encoded = String(data: data, encoding: .utf8)
        else { fatalError("Synthetic shortcut preferences could not be encoded") }
        return encoded
    }

    func shortcutChanged(_ shortcut: KeyboardShortcuts.Shortcut?) {
        shortcutWarning = shortcut.flatMap { ShortcutConflicts.conflict(with: "\($0)") }
        changes += 1
    }

    func writeSnapshot() {
        let panel = KeyboardShortcuts.getShortcut(for: .togglePanel)
        let cyclic = KeyboardShortcuts.getShortcut(for: .cyclicPaste)
        let displayed = displayedRecorders()
        let bound = boundMenuShortcut()
        let state: [String: Any] = [
            "bundleIdentifier": identifier,
            "version": Bundle.main.object(forInfoDictionaryKey: "FixtureDependencyVersion")
                as? String ?? "missing",
            "revision": Bundle.main.object(forInfoDictionaryKey: "FixtureDependencyRevision")
                as? String ?? "missing",
            "seededValues": seededValues,
            "storedValues": Self.storedValues(identifier: identifier),
            "panelDown": panelDown, "panelUp": panelUp,
            "cyclicDown": cyclicDown, "cyclicUp": cyclicUp,
            "changes": changes, "recordingActive": recordingActive,
            "recordersReady": displayed["toggle-panel"] != nil && displayed["cyclic-paste"] != nil,
            "panelKeyCode": panel?.carbonKeyCode ?? -1,
            "panelModifiers": panel?.carbonModifiers ?? -1,
            "cyclicKeyCode": cyclic?.carbonKeyCode ?? -1,
            "cyclicModifiers": cyclic?.carbonModifiers ?? -1,
            "panelEnabled": KeyboardShortcuts.isEnabled(for: .togglePanel),
            "cyclicEnabled": KeyboardShortcuts.isEnabled(for: .cyclicPaste),
            "panelDisplay": displayed["toggle-panel"] ?? "",
            "cyclicDisplay": displayed["cyclic-paste"] ?? "",
            "boundMenuKey": bound.key, "boundMenuModifiers": bound.modifiers
        ]
        do {
            let data = try JSONSerialization.data(
                withJSONObject: state, options: [.sortedKeys, .prettyPrinted])
            try data.write(to: snapshotURL, options: .atomic)
        } catch {
            fatalError("Could not save synthetic recorder state: \(error)")
        }
    }
}

private struct RecorderFixtureView: View {
    let state: RecorderFixtureState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Shortcut Recorder Fixture").font(.title)
            KeyboardShortcuts.Recorder("Panel shortcut:", name: .togglePanel) { shortcut in
                state.shortcutChanged(shortcut)
            }
            .accessibilityIdentifier("panel-shortcut-recorder")
            KeyboardShortcuts.Recorder("Cyclic paste shortcut:", name: .cyclicPaste) { shortcut in
                state.shortcutChanged(shortcut)
            }
            .accessibilityIdentifier("cyclic-shortcut-recorder")
            if let warning = state.shortcutWarning {
                Text("This shortcut is used by the system (\(warning)).")
            }
            Button("Stop recording") { NSApp.keyWindow?.makeFirstResponder(nil) }
                .accessibilityIdentifier("stop-recording-button")
            Text(state.recordingActive ? "Recording" : "Ready")
                .accessibilityIdentifier("recorder-state-text")
            Text(
                "Panel \(state.panelDown)/\(state.panelUp); cyclic \(state.cyclicDown)/\(state.cyclicUp)"
            )
            .font(.system(.body, design: .monospaced))
        }
        .padding(28)
        .frame(width: 540, height: 260)
    }
}

@main
@MainActor
final class ShortcutRecorderFixture: NSObject, NSApplicationDelegate {
    private var window: NSWindow?
    private var state: RecorderFixtureState?
    private var snapshotTimer: Timer?

    static func main() {
        let app = NSApplication.shared
        let delegate = ShortcutRecorderFixture()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let state = RecorderFixtureState()
        self.state = state

        let fixtureMenu = NSMenu(title: "Fixture Menu")
        let reserved = NSMenuItem(
            title: "Reserved Fixture Action", action: #selector(reservedAction), keyEquivalent: "j")
        reserved.target = self
        reserved.keyEquivalentModifierMask = .command
        fixtureMenu.addItem(reserved)
        let bound = NSMenuItem(
            title: "Current Panel Binding", action: #selector(reservedAction), keyEquivalent: "")
        bound.target = self
        bound.setShortcut(for: .togglePanel)
        fixtureMenu.addItem(bound)
        state.boundMenuShortcut = { [weak bound] in
            (bound?.keyEquivalent ?? "", bound?.keyEquivalentModifierMask.rawValue ?? 0)
        }
        let mainMenu = NSMenu()
        let item = NSMenuItem(title: "Fixture Menu", action: nil, keyEquivalent: "")
        item.submenu = fixtureMenu
        mainMenu.addItem(item)
        NSApp.mainMenu = mainMenu

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 596, height: 316),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "Shortcut Recorder Fixture"
        window.contentView = NSHostingView(rootView: RecorderFixtureView(state: state))
        state.displayedRecorders = { [weak window] in
            Self.recorders(in: window?.contentView).reduce(into: [:]) { values, recorder in
                values[recorder.shortcutName.rawValue] = recorder.stringValue
            }
        }
        window.center()
        window.makeKeyAndOrderFront(nil)
        self.window = window
        snapshotTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) {
            [weak state] _ in
            Task { @MainActor [weak state] in state?.writeSnapshot() }
        }
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        state.writeSnapshot()
    }

    private static func recorders(in view: NSView?) -> [KeyboardShortcuts.RecorderCocoa] {
        guard let view else { return [] }
        if let recorder = view as? KeyboardShortcuts.RecorderCocoa { return [recorder] }
        return view.subviews.flatMap { recorders(in: $0) }
    }

    @objc private func reservedAction() {}

    func applicationWillTerminate(_ notification: Notification) {
        snapshotTimer?.invalidate()
        state?.writeSnapshot()
        // Preserve this UUID domain across test-owned relaunches. The runner
        // removes it only after each complete case, including failure paths.
        UserDefaults.standard.synchronize()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

import AppKit
import KeyboardShortcuts

/// A disposable dependency host. It never starts Gancho's composition root.
@MainActor
final class MenuFixtureState {
    var menuTracking = false
    var keyDownCount = 0
    var keyUpCount = 0
    var trace: [[String: Any]] = []
    let snapshotURL: URL

    init() {
        let arguments = CommandLine.arguments
        let prefix = "com.johnny4young.gancho.tests.shortcut-menu."
        guard let identifier = Bundle.main.bundleIdentifier,
            identifier.hasPrefix(prefix),
            identifier.dropFirst(prefix.count).count == 32,
            identifier.dropFirst(prefix.count).allSatisfy({ "0123456789abcdef".contains($0) }),
            let index = arguments.firstIndex(of: "-fixture-snapshot"),
            arguments.indices.contains(index + 1)
        else { fatalError("An isolated fixture identity and snapshot are required") }
        snapshotURL = URL(fileURLWithPath: arguments[index + 1]).standardizedFileURL
        guard snapshotURL.lastPathComponent == "snapshot.json",
            snapshotURL.deletingLastPathComponent().lastPathComponent.hasPrefix(
                "gancho-shortcut-menu.")
        else { fatalError("Snapshot must belong to the disposable fixture directory") }

        // Reset only the fresh UUID fixture domain; never Gancho's preferences.
        UserDefaults.standard.removePersistentDomain(forName: identifier)
        KeyboardShortcuts.setShortcut(
            .init(.v, modifiers: [.command, .control, .option, .shift]), for: .togglePanel)
        KeyboardShortcuts.onKeyDown(for: .togglePanel) { [weak self] in
            guard let self else { return }
            keyDownCount += 1
            record("down-callback", event: NSApp.currentEvent)
        }
        KeyboardShortcuts.onKeyUp(for: .togglePanel) { [weak self] in
            guard let self else { return }
            keyUpCount += 1
            record("up-callback", event: NSApp.currentEvent)
        }
        writeSnapshot()
    }

    func record(_ phase: String, event: NSEvent? = nil, mode: RunLoop.Mode? = nil) {
        var entry: [String: Any] = ["phase": phase, "menuTracking": menuTracking]
        if let event {
            // Collect metadata only for the fixture chord, never key characters.
            guard [.keyDown, .keyUp].contains(event.type), event.keyCode == 9,
                event.modifierFlags.intersection(.deviceIndependentFlagsMask)
                    == [.command, .control, .option, .shift]
            else { return }
            entry["type"] = event.type.rawValue
            entry["timestamp"] = event.timestamp
            entry["isRepeat"] = event.isARepeat
            entry["keyCode"] = event.keyCode
            entry["modifiers"] = event.modifierFlags.rawValue
        }
        if let mode { entry["mode"] = mode.rawValue }
        trace.append(entry)
        writeSnapshot()
    }

    func writeSnapshot() {
        let shortcut = KeyboardShortcuts.getShortcut(for: .togglePanel)
        let state: [String: Any] = [
            "bundleIdentifier": Bundle.main.bundleIdentifier ?? "missing",
            "version": Bundle.main.object(forInfoDictionaryKey: "FixtureDependencyVersion")
                as? String ?? "missing",
            "revision": Bundle.main.object(forInfoDictionaryKey: "FixtureDependencyRevision")
                as? String ?? "missing",
            "shortcutEnabled": KeyboardShortcuts.isEnabled(for: .togglePanel),
            "shortcutKeyCode": shortcut?.carbonKeyCode ?? -1,
            "shortcutModifiers": shortcut?.carbonModifiers ?? -1,
            "menuTracking": menuTracking,
            "keyDownCount": keyDownCount, "keyUpCount": keyUpCount, "trace": trace
        ]
        do {
            let data = try JSONSerialization.data(
                withJSONObject: state, options: [.sortedKeys, .prettyPrinted])
            try data.write(to: snapshotURL, options: .atomic)
        } catch {
            fatalError("Could not save synthetic fixture event metadata: \(error)")
        }
    }
}

@main
@MainActor
final class ShortcutMenuFixture: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var window: NSWindow?
    private var menu: NSMenu?

    static func main() {
        let app = MenuFixtureApplication.shared
        let delegate = ShortcutMenuFixture()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let state = MenuFixtureState()
        (NSApp as? MenuFixtureApplication)?.fixtureState = state

        let fixtureMenu = NSMenu(title: "Fixture Menu")
        fixtureMenu.delegate = self
        fixtureMenu.addItem(
            withTitle: "Reserved Fixture Action", action: #selector(reservedAction),
            keyEquivalent: "j")
        fixtureMenu.items.last?.target = self
        let boundItem = NSMenuItem(
            title: "Current Panel Binding", action: #selector(reservedAction), keyEquivalent: "")
        boundItem.target = self
        boundItem.setShortcut(for: .togglePanel)
        fixtureMenu.addItem(boundItem)
        menu = fixtureMenu

        let mainMenu = NSMenu()
        let menuItem = NSMenuItem(title: "Fixture Menu", action: nil, keyEquivalent: "")
        menuItem.submenu = fixtureMenu
        mainMenu.addItem(menuItem)
        NSApp.mainMenu = mainMenu

        let fixtureWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 180),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        fixtureWindow.title = "Shortcut Menu Fixture"
        let button = NSButton(title: "Open fixture menu", target: self, action: #selector(openMenu))
        button.frame = NSRect(x: 80, y: 70, width: 260, height: 36)
        button.setAccessibilityIdentifier("open-menu-button")
        fixtureWindow.contentView?.addSubview(button)
        fixtureWindow.center()
        fixtureWindow.makeKeyAndOrderFront(nil)
        window = fixtureWindow
        NSRunningApplication.current.activate(options: [.activateAllWindows])
    }

    @objc private func openMenu() {
        guard let view = window?.contentView else { return }
        menu?.popUp(positioning: nil, at: NSPoint(x: 100, y: 110), in: view)
    }

    @objc private func reservedAction() {}

    func menuWillOpen(_ menu: NSMenu) {
        let state = (NSApp as? MenuFixtureApplication)?.fixtureState
        state?.menuTracking = true
        state?.record("menu-open")
    }

    func menuDidClose(_ menu: NSMenu) {
        let state = (NSApp as? MenuFixtureApplication)?.fixtureState
        state?.menuTracking = false
        state?.record("menu-close")
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let identifier = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: identifier)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

/// Observe forwarding without changing the return value or event route.
@objc(MenuFixtureApplication)
@MainActor
final class MenuFixtureApplication: NSApplication {
    var fixtureState: MenuFixtureState?

    override func nextEvent(
        matching mask: NSEvent.EventTypeMask, until expiration: Date?,
        inMode mode: RunLoop.Mode, dequeue: Bool
    ) -> NSEvent? {
        let event = super.nextEvent(
            matching: mask, until: expiration, inMode: mode, dequeue: dequeue)
        if dequeue, let event { fixtureState?.record("dequeue", event: event, mode: mode) }
        return event
    }

    override func postEvent(_ event: NSEvent, atStart: Bool) {
        fixtureState?.record("repost", event: event)
        super.postEvent(event, atStart: atStart)
    }

    override func sendEvent(_ event: NSEvent) {
        fixtureState?.record("send", event: event)
        super.sendEvent(event)
    }
}

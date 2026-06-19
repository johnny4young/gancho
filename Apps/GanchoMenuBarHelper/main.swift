import AppKit

/// Paint-only menu-bar helper.
///
/// A separate, minimal process owns the visible `NSStatusItem` so the main app's
/// scene lifecycle can't keep the icon hidden. It reads only content-free data
/// from the shared App Group (`GanchoMenuBarBridge`): the status glyph, the
/// localized menu titles, and the command nonce. It performs no clipboard work —
/// every menu click is forwarded to the main app as a nonce-stamped deep link.
@MainActor
private final class MenuBarHelperDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let mainAppBundleID = "com.johnny4young.gancho"

    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    private var watchdog: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ProcessInfo.processInfo.disableAutomaticTermination(
            "Gancho keeps a resident menu-bar helper")

        menu.autoenablesItems = false
        menu.delegate = self

        let item = NSStatusBar.system.statusItem(withLength: GanchoMenuBarCommand.statusItemLength)
        item.menu = menu
        item.isVisible = true
        statusItem = item

        applyStatusPresentation()
        rebuildMenu()
        startWatchdog()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
        applyStatusPresentation()
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        let titles = GanchoMenuBarBridge.readTitles()
        let status = GanchoMenuBarBridge.readStatus()

        // A glanceable state header (content-free: the status label + a colored
        // dot, both already localized/derived by the app — no clipboard data).
        let header = NSMenuItem(title: status.label, action: nil, keyEquivalent: "")
        header.isEnabled = false
        header.image = status.icon.statusDot()
        menu.addItem(header)

        for section in GanchoMenuBarCommand.helperMenuSections {
            menu.addItem(.separator())
            for command in section {
                let item = NSMenuItem(
                    title: titles[command.rawValue] ?? command.helperTitle,
                    action: #selector(performCommand(_:)),
                    keyEquivalent: command.keyEquivalent)
                item.target = self
                item.keyEquivalentModifierMask = command.modifiers
                item.representedObject = command.rawValue
                item.setAccessibilityIdentifier(command.accessibilityIdentifier)
                item.setAccessibilityLabel(command.accessibilityLabel)
                menu.addItem(item)
            }
        }
    }

    private func applyStatusPresentation() {
        guard let button = statusItem?.button else { return }
        let status = GanchoMenuBarBridge.readStatus()
        button.image = status.icon.templateImage()
        button.imagePosition = .imageOnly
        button.title = ""
        button.toolTip = status.label
        button.setAccessibilityLabel(status.label)
    }

    private func startWatchdog() {
        watchdog = Timer.scheduledTimer(
            timeInterval: 1.5,
            target: self,
            selector: #selector(tick),
            userInfo: nil,
            repeats: true)
    }

    @objc private func tick() {
        // Exit when the main app is gone — works whether we were launched by
        // launchd (SMAppService) or by the app directly (Process fallback).
        let mainAppRunning =
            !NSRunningApplication
            .runningApplications(withBundleIdentifier: Self.mainAppBundleID).isEmpty
        guard mainAppRunning else {
            NSApp.terminate(nil)
            return
        }
        // Reflect the latest content-free status (#3 dynamic icon).
        applyStatusPresentation()
    }

    @objc private func performCommand(_ sender: NSMenuItem) {
        guard
            let rawValue = sender.representedObject as? String,
            let command = GanchoMenuBarCommand(rawValue: rawValue)
        else { return }

        let token = GanchoMenuBarBridge.readNonce() ?? ""
        NSWorkspace.shared.open(command.deepLinkURL(token: token))

        if command == .quit {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                NSApp.terminate(nil)
            }
        }
    }
}

private let delegate = MenuBarHelperDelegate()
private let application = NSApplication.shared
application.delegate = delegate
application.run()

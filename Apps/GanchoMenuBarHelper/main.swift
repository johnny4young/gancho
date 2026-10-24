import AppKit

/// Paint-only menu-bar helper.
///
/// A separate, minimal process owns the visible `NSStatusItem` so the main app's
/// scene lifecycle can't keep the icon hidden. It reads only content-free bridge
/// state (status label and badge, localized titles, the command nonce) and
/// never touches the clipboard or the history. A click asks the main app to
/// open its own menu under the icon; ⌥ and ⌥⇧ clicks become commands. Every
/// request is a nonce-stamped distributed notification.
@MainActor
private final class MenuBarHelperDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private static let mainAppBundleID = "com.johnny4young.gancho"
    /// How long the app has to open its menu before the helper shows its own.
    private static let menuAnswerTimeout: Duration = .milliseconds(500)

    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    private var watchdog: Timer?
    private var pendingMenuFallback: Task<Void, Never>?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        ProcessInfo.processInfo.disableAutomaticTermination(
            "Gancho keeps a resident menu-bar helper")

        menu.autoenablesItems = false
        menu.delegate = self

        let item = NSStatusBar.system.statusItem(withLength: GanchoMenuBarCommand.statusItemLength)
        // The helper exits immediately if the user Command-drags its icon out
        // of the menu bar; the main app's reciprocal watchdog then closes the
        // in-memory history process too.
        item.behavior = .terminationOnRemoval
        item.button?.target = self
        item.button?.action = #selector(statusItemClicked)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        item.isVisible = true
        statusItem = item

        observeMenuSignals()
        applyStatusPresentation()
        startWatchdog()
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu()
    }

    @objc private func statusItemClicked() {
        switch MenuBarClick(modifiers: NSApp.currentEvent?.modifierFlags ?? []) {
        case .command(let command):
            guard let token = GanchoMenuBarBridge.readNonce(), !token.isEmpty else { return }
            command.postDistributed(token: token)
        case .openMenu:
            requestAppMenu()
        }
    }

    /// Hands the click to the app, which draws the menu with the recent clips.
    /// If it doesn't answer in time (busy or gone), the helper's own command
    /// menu opens instead, so a click is never lost.
    private func requestAppMenu() {
        guard let button = statusItem?.button, let window = button.window else { return }
        guard let token = GanchoMenuBarBridge.readNonce(), !token.isEmpty else {
            showOwnMenu()
            return
        }
        GanchoMenuBarBridge.writeButtonFrame(window.convertToScreen(button.frame))
        button.highlight(true)
        GanchoMenuBarSignal.showMenu.post(token: token)
        pendingMenuFallback?.cancel()
        pendingMenuFallback = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.menuAnswerTimeout)
            guard !Task.isCancelled else { return }
            self?.showOwnMenu()
        }
    }

    private func showOwnMenu() {
        guard let statusItem, let button = statusItem.button else { return }
        button.highlight(false)
        statusItem.menu = menu
        button.performClick(nil)
        statusItem.menu = nil
    }

    private func observeMenuSignals() {
        let center = DistributedNotificationCenter.default()
        for signal in [GanchoMenuBarSignal.menuDidOpen, .menuDidClose] {
            center.addObserver(
                self, selector: #selector(receiveMenuSignal(_:)),
                name: signal.distributedNotificationName, object: nil,
                suspensionBehavior: .deliverImmediately)
        }
    }

    @objc private func receiveMenuSignal(_ notification: Notification) {
        guard let token = notification.object as? String,
            token == GanchoMenuBarBridge.readNonce()
        else { return }
        pendingMenuFallback?.cancel()
        pendingMenuFallback = nil
        let opened =
            notification.name == GanchoMenuBarSignal.menuDidOpen.distributedNotificationName
        statusItem?.button?.highlight(opened)
    }

    private func rebuildMenu() {
        menu.removeAllItems()
        let titles = GanchoMenuBarBridge.readTitles()
        let status = GanchoMenuBarBridge.readStatus()

        let header = NSMenuItem(title: status.label, action: nil, keyEquivalent: "")
        header.isEnabled = false
        header.image = MenuBarGlyph.stateDot(for: status.badge)
        menu.addItem(header)

        var sections = GanchoMenuBarCommand.helperMenuSections
        if status.badge == .denied { sections.insert([.fixClipboardAccess], at: 0) }
        for section in sections {
            menu.addItem(.separator())
            for command in section {
                let item = NSMenuItem(
                    title: titles[command.rawValue] ?? command.helperTitle,
                    action: #selector(performCommand(_:)),
                    keyEquivalent: command.keyEquivalent)
                item.target = self
                item.keyEquivalentModifierMask = command.modifiers
                if command == .openPanel {
                    GanchoMenuBarBridge.readPanelShortcut()?.apply(to: item)
                }
                item.representedObject = command.rawValue
                item.image = NSImage(
                    systemSymbolName: command.iconSymbol, accessibilityDescription: nil)
                item.setAccessibilityIdentifier(command.accessibilityIdentifier)
                item.setAccessibilityLabel(command.accessibilityLabel)
                menu.addItem(item)
            }
        }
    }

    private func applyStatusPresentation() {
        guard let button = statusItem?.button else { return }
        let status = GanchoMenuBarBridge.readStatus()
        MenuBarGlyph.apply(badge: status.badge, to: button)
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
        // A removed/hidden status item is equivalent to losing the helper: ask
        // the main app to quit, then exit so its reciprocal watchdog also sees
        // the loss even if the notification is dropped or process termination
        // is denied. No clipboard-history process may survive without an icon.
        guard statusItem?.isVisible == true else {
            requestMainAppTermination()
            NSApp.terminate(nil)
            return
        }

        // Exit when the main app is gone — works whether we were launched by
        // launchd (SMAppService) or by the app directly (Process fallback).
        guard !mainAppInstances.isEmpty else {
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

        if command == .quit {
            // The distributed command asks the main app to quit cleanly. But a
            // dropped notification (or a nonce mismatch) must NEVER strand it
            // as a live, icon-less agent, so terminate it directly too — belt
            // and suspenders.
            // We do NOT self-terminate on a timer here (the old behavior): the
            // watchdog exits us the moment the main app is actually gone, so if
            // the main app somehow refuses to quit we stay resident with the icon
            // present (the user can retry) instead of orphaning it.
            requestMainAppTermination()
        } else {
            guard let token = GanchoMenuBarBridge.readNonce(), !token.isEmpty else { return }
            command.postDistributed(token: token)
        }
    }

    private func requestMainAppTermination() {
        if let token = GanchoMenuBarBridge.readNonce(), !token.isEmpty {
            GanchoMenuBarCommand.quit.postDistributed(token: token)
        }
        for app in mainAppInstances {
            app.terminate()
        }
    }

    /// The raw helper is embedded inside Gancho.app, so LaunchServices attributes
    /// it to the container bundle identifier too. Exclude this executable and
    /// match the containing bundle path; otherwise the watchdog can mistake the
    /// helper itself (or another installed Gancho) for its owning main process.
    private var mainAppInstances: [NSRunningApplication] {
        let currentProcessID = ProcessInfo.processInfo.processIdentifier
        let mainBundleURL = Bundle.main.bundleURL.standardizedFileURL
        return NSRunningApplication.runningApplications(
            withBundleIdentifier: Self.mainAppBundleID
        ).filter { app in
            app.processIdentifier != currentProcessID
                && app.executableURL?.lastPathComponent != "GanchoMenuBarHelper"
                && app.bundleURL?.standardizedFileURL == mainBundleURL
        }
    }
}

private let delegate = MenuBarHelperDelegate()
private let application = NSApplication.shared
application.delegate = delegate
application.run()

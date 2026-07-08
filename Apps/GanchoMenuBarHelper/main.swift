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

        // The most recent clip (masked by the app; absent in private mode and
        // when no app-group bridge is present). Clicking it opens the panel.
        if let recent = GanchoMenuBarBridge.readLastCopied() {
            menu.addItem(lastCopiedItem(recent))
        }

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
                item.image = NSImage(
                    systemSymbolName: command.iconSymbol, accessibilityDescription: nil)
                item.setAccessibilityIdentifier(command.accessibilityIdentifier)
                item.setAccessibilityLabel(command.accessibilityLabel)
                menu.addItem(item)
            }
        }
    }

    /// A two-line recent row: the masked preview over a "<label> · <when>"
    /// caption with a link glyph. Opens the panel on click.
    private func lastCopiedItem(_ recent: (preview: String, label: String, at: Date)) -> NSMenuItem
    {
        let item = NSMenuItem(
            title: "", action: #selector(performCommand(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = GanchoMenuBarCommand.openPanel.rawValue
        item.image = NSImage(systemSymbolName: "link", accessibilityDescription: nil)

        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        let when = formatter.localizedString(for: recent.at, relativeTo: Date())

        let title = NSMutableAttributedString(
            string: recent.preview + "\n",
            attributes: [.font: NSFont.menuFont(ofSize: 0), .foregroundColor: NSColor.labelColor])
        title.append(
            NSAttributedString(
                string: "\(recent.label) · \(when)",
                attributes: [
                    .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
                    .foregroundColor: NSColor.secondaryLabelColor,
                ]))
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        title.addAttribute(
            .paragraphStyle, value: paragraph, range: NSRange(location: 0, length: title.length))
        item.attributedTitle = title
        item.setAccessibilityLabel("\(recent.label): \(recent.preview)")
        return item
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
            // The deep link asks the main app to quit cleanly. But a dropped open
            // event (or a nonce mismatch) must NEVER strand it as a live,
            // icon-less agent, so terminate it directly too — belt and suspenders.
            // We do NOT self-terminate on a timer here (the old behavior): the
            // watchdog exits us the moment the main app is actually gone, so if
            // the main app somehow refuses to quit we stay resident with the icon
            // present (the user can retry) instead of orphaning it.
            for app in NSRunningApplication.runningApplications(
                withBundleIdentifier: Self.mainAppBundleID)
            {
                app.terminate()
            }
        }
    }
}

private let delegate = MenuBarHelperDelegate()
private let application = NSApplication.shared
application.delegate = delegate
application.run()

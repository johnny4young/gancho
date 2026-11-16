import AppKit
import GanchoAppCore
import GanchoDesign
import GanchoKit
import KeyboardShortcuts
import SwiftUI

/// The status item's menu as a mini-panel: the capture state, five recent clips
/// with their tiles (⌘1–5, ⌥ pastes plain), the paste stack and the commands.
/// The main app draws it for both the helper's icon and its own fallback, so
/// no clip ever leaves this process.
@MainActor
final class MenuBarMenu: NSObject, NSMenuDelegate {
    private static let tileSide: CGFloat = 18
    private static let titleLimit = 46
    private static let tileCacheLimit = 32

    private struct TileKey: Hashable {
        let id: UUID
        let contentHash: String
        let kind: ClipContentKind
        let hidden: Bool
        let dark: Bool
        let hasThumbnail: Bool
    }

    let menu = NSMenu()
    private weak var model: AppModel?
    private var pausedPanelShortcut = false
    private var tiles: [TileKey: NSImage] = [:]
    /// Called as the menu opens and closes; the helper path forwards them.
    var onOpen: () -> Void = {}
    var onClose: () -> Void = {}

    init(model: AppModel) {
        self.model = model
        super.init()
        menu.autoenablesItems = false
        menu.delegate = self
    }

    /// Opens the menu with its top-left corner at a screen point.
    func popUp(atScreenPoint point: NSPoint) {
        rebuild()
        menu.popUp(positioning: nil, at: point, in: nil)
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuild()
    }

    /// Open panel carries the global panel shortcut; while the menu tracks, a
    /// hotkey press would be buffered and toggle the panel again on close.
    func menuWillOpen(_ menu: NSMenu) {
        if KeyboardShortcuts.isEnabled(for: .togglePanel) {
            KeyboardShortcuts.disable(.togglePanel)
            pausedPanelShortcut = true
        }
        model?.acknowledgeAgentRead()
        onOpen()
    }

    func menuDidClose(_ menu: NSMenu) {
        if pausedPanelShortcut {
            KeyboardShortcuts.enable(.togglePanel)
            pausedPanelShortcut = false
        }
        onClose()
    }

    private func rebuild() {
        menu.removeAllItems()
        guard let model else { return }
        let plan = MenuBarMenuPlan(
            recents: model.recentItems,
            stack: model.pasteStackWaiting,
            previewsHidden: model.previewsHidden,
            accessDenied: model.monitorStatus == .deniedByPrivacySettings)
        for entry in plan.entries {
            switch entry {
            case .header: menu.addItem(header(model))
            case .recentsLabel: menu.addItem(recentsLabel())
            case .recent(let recent):
                menu.addItem(recentItem(recent, model: model, plain: false))
                menu.addItem(recentItem(recent, model: model, plain: true))
            case .noRecents:
                let item = NSMenuItem(
                    title: String(localized: "Copy something — it will appear here."),
                    action: nil, keyEquivalent: "")
                item.isEnabled = false
                menu.addItem(item)
            case .stack(let stack): menu.addItem(stackItem(stack, model: model))
            case .command(let command):
                menu.addItem(commandItem(GanchoMenuBarCommand(command), model: model))
            case .separator: menu.addItem(.separator())
            }
        }
    }

    // MARK: Rows

    /// "Capturing · 128 clips · Keynote in front", with the state's dot.
    private func header(_ model: AppModel) -> NSMenuItem {
        let chip = model.captureChip(frontApp: model.pasteTarget.appName)
        var parts = [Self.stateTitle(chip)]
        if let count = model.menuBarClipCount { parts.append(String(localized: "\(count) clips")) }
        if case .capturing(let app?) = chip { parts.append(String(localized: "\(app) in front")) }
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(
            string: parts.joined(separator: " · "),
            attributes: [.font: NSFont.menuFont(ofSize: 0).bold])
        item.image = MenuBarGlyph.stateDot(for: Self.dotState(chip))
        item.isEnabled = false
        item.setAccessibilityIdentifier("menu-bar-header")
        return item
    }

    private func recentsLabel() -> NSMenuItem {
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.attributedTitle = NSAttributedString(
            string: String(localized: "Recent · click pastes · ⌥ pastes plain")
                .uppercased(with: .current),
            attributes: [
                .font: GanchoType.nsFont(.data, size: 9.5, weight: .medium)
                    ?? .monospacedSystemFont(ofSize: 9.5, weight: .medium),
                .foregroundColor: NSColor.secondaryLabelColor, .kern: 0.6
            ])
        item.isEnabled = false
        return item
    }

    /// The plain twin is an alternate: it replaces its row while ⌥ is held.
    private func recentItem(
        _ recent: MenuBarMenuPlan.Recent, model: AppModel, plain: Bool
    ) -> NSMenuItem {
        let item = NSMenuItem(
            title: Self.title(for: recent.clip, masked: recent.masked),
            action: #selector(pasteRecent(_:)), keyEquivalent: "\(recent.number)")
        item.keyEquivalentModifierMask = plain ? [.command, .option] : [.command]
        item.isAlternate = plain
        item.target = self
        item.representedObject = RecentPaste(clip: recent.clip, plain: plain)
        item.image = tile(for: recent.clip, model: model)
        item.setAccessibilityIdentifier(
            plain ? "menu-bar-recent-plain-\(recent.number)" : "menu-bar-recent-\(recent.number)")
        return item
    }

    private func stackItem(_ stack: MenuBarMenuPlan.Stack, model: AppModel) -> NSMenuItem {
        let item = NSMenuItem(
            title: "", action: #selector(pasteNextFromStack), keyEquivalent: "")
        item.target = self
        let title = NSMutableAttributedString(
            string: String(localized: "Paste stack · \(stack.waiting) waiting") + "\n",
            attributes: [.font: NSFont.menuFont(ofSize: 0)])
        title.append(
            NSAttributedString(
                string: String(
                    localized: "next: \(Self.title(for: stack.next, masked: stack.nextMasked))"),
                attributes: [
                    .font: NSFont.menuFont(ofSize: NSFont.smallSystemFontSize),
                    .foregroundColor: NSColor.secondaryLabelColor
                ]))
        item.attributedTitle = title
        item.setShortcut(for: .pasteFromStack)
        item.image = NSImage(
            systemSymbolName: "square.stack.3d.up", accessibilityDescription: nil)
        item.setAccessibilityIdentifier("menu-bar-paste-stack")
        return item
    }

    private func commandItem(_ command: GanchoMenuBarCommand, model: AppModel) -> NSMenuItem {
        let item = NSMenuItem(
            title: command.title(captureIsRunning: model.monitorStatus == .running),
            action: #selector(performCommand(_:)), keyEquivalent: command.keyEquivalent)
        item.target = self
        item.keyEquivalentModifierMask = command.modifiers
        switch command {
        case .openPanel:
            item.setShortcut(for: .togglePanel)
            #if DEBUG
                if CommandLine.arguments.contains("-diagnose-menu-shortcut-for-ui-test") {
                    item.setAccessibilityValue(
                        "menu-shortcut:\(item.keyEquivalent):\(item.keyEquivalentModifierMask.rawValue)"
                    )
                }
            #endif
        case .copyScreenText:
            item.setShortcut(for: .copyScreenText)
            item.isEnabled = model.canCopyScreenText
        case .togglePrivateMode:
            item.setShortcut(for: .togglePrivateMode)
            item.state = model.preferences.isPrivateModePaused ? .on : .off
        default: break
        }
        item.representedObject = command.rawValue
        item.image = NSImage(systemSymbolName: command.iconSymbol, accessibilityDescription: nil)
        item.setAccessibilityIdentifier(command.accessibilityIdentifier)
        item.setAccessibilityLabel(command.accessibilityLabel)
        return item
    }

    // MARK: Actions

    private struct RecentPaste {
        let clip: ClipItem
        let plain: Bool
    }

    @objc private func pasteRecent(_ sender: NSMenuItem) {
        guard let paste = sender.representedObject as? RecentPaste else { return }
        model?.paste(paste.clip, asPlainText: paste.plain)
    }

    @objc private func pasteNextFromStack() {
        model?.pasteNextFromStack()
    }

    @objc private func performCommand(_ sender: NSMenuItem) {
        guard let rawValue = sender.representedObject as? String,
            let command = GanchoMenuBarCommand(rawValue: rawValue), let model
        else { return }
        command.perform(on: model)
    }

    // MARK: Presentation

    /// The clip's first line, cut short; a masked clip shows only its kind.
    private static func title(for clip: ClipItem, masked: Bool) -> String {
        guard !masked else {
            let kind = clip.kind.localizedName
            return String(localized: "\(kind) · masked")
        }
        let headline = ClipRowContent(item: clip).headline.line
        let line = headline.isEmpty ? clip.kind.localizedName : headline
        return line.count > titleLimit ? String(line.prefix(titleLimit - 1)) + "…" : line
    }

    /// The row's tile as an image. A protected clip's ring is drawn as it
    /// stands, so only tiles without a lifetime are cached.
    private func tile(for clip: ClipItem, model: AppModel) -> NSImage? {
        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let hidden = model.previewsHidden
        let masked = hidden || ClipSafePresentation.requiresMasking(clip)
        let thumbnail = masked ? nil : model.thumbnails.cached(for: clip)
        let key = TileKey(
            id: clip.id, contentHash: clip.contentHash, kind: clip.kind, hidden: hidden,
            dark: isDark,
            hasThumbnail: thumbnail != nil)
        if clip.expiresAt == nil, let cached = tiles[key] { return cached }
        let renderer = ImageRenderer(
            content: ClipTile(
                item: clip, size: Self.tileSide, previewsHidden: hidden, thumbnail: thumbnail
            )
            .environment(\.colorScheme, isDark ? .dark : .light))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage
        if clip.expiresAt == nil, let image {
            if tiles.count >= Self.tileCacheLimit { tiles.removeAll() }
            tiles[key] = image
        }
        return image
    }

    static func stateTitle(_ chip: PanelCaptureChip) -> String {
        switch chip {
        case .capturing: String(localized: "Capturing")
        case .privateMode(let end?):
            String(
                localized:
                    "Private mode · \(PanelCaptureChip.minutesLeft(until: end, now: .now)) min left"
            )
        case .privateMode: String(localized: "Private mode")
        case .paused(.screenShare): String(localized: "Paused · screen sharing")
        case .paused(.screenLock): String(localized: "Paused · screen locked")
        case .paused(.user): String(localized: "Paused")
        case .denied: String(localized: "Access denied")
        }
    }

    /// The header dot follows the header's own state.
    private static func dotState(_ chip: PanelCaptureChip) -> MenuBarBadge? {
        switch chip {
        case .capturing: nil
        case .privateMode: .privateMode
        case .paused: .paused
        case .denied: .denied
        }
    }
}

extension GanchoMenuBarCommand {
    init(_ command: MenuBarMenuPlan.Command) {
        self =
            switch command {
            case .openPanel: .openPanel
            case .library: .library
            case .copyScreenText: .copyScreenText
            case .toggleCapture: .toggleCapture
            case .togglePrivateMode: .togglePrivateMode
            case .ignoreNextCopy: .ignoreNextCopy
            case .settings: .settings
            case .privacyCenter: .privacyCenter
            case .welcome: .welcome
            case .wrapped: .wrapped
            case .fixClipboardAccess: .fixClipboardAccess
            case .quit: .quit
            }
    }
}

extension NSFont {
    fileprivate var bold: NSFont {
        NSFontManager.shared.convert(self, toHaveTrait: .boldFontMask)
    }
}

extension ClipRowContent.Headline {
    /// The headline as one plain line: a link reads host first, without its scheme.
    var line: String {
        switch self {
        case .text(let text), .value(let text), .code(let text): text
        case .link(let host, let path): host + (path ?? "")
        case .kindName(let kind): kind.localizedName
        }
    }
}

extension ClipContentKind {
    /// The kind's name as the app's catalog spells it: what a masked clip shows.
    var localizedName: String {
        Bundle.main.localizedString(forKey: rawValue, value: nil, table: nil)
    }
}

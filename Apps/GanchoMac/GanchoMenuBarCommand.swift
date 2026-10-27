import AppKit
import Foundation

#if !STANDALONE_MENU_BAR
    import GanchoKit
#endif

/// Shared command metadata for Gancho's menu-bar surfaces.
///
/// Command titles, shortcuts, symbols, and accessibility identifiers live in
/// one enum so menus and equivalent controls cannot drift: the in-process
/// `NSStatusItem` fallback and the external paint-only helper both render this
/// command surface, while the main app remains the only process that performs
/// private clipboard work.
enum GanchoMenuBarCommand: String, CaseIterable {
    case copyScreenText
    case library
    case openPanel
    case toggleCapture
    case togglePrivateMode
    case ignoreNextCopy
    case settings
    case welcome
    case privacyCenter
    case wrapped
    case fixClipboardAccess
    case quit

    static let appTitle = String(localized: "Gancho")
    /// Let the status item hug its template image (the hook ~18 pt) plus the
    /// system's standard padding, instead of a fixed slot that left the mark
    /// floating in too much width. Used by both the in-process item and the helper.
    static let statusItemLength = NSStatusItem.variableLength
    static let statusAccessibilityLabel = String(localized: "Gancho")

    /// A content-free cross-process command channel. Each command gets its own
    /// notification name and carries only the per-launch nonce as `object`, so
    /// it remains valid for sandboxed builds (distributed notifications forbid
    /// `userInfo` dictionaries there) and never needs Automation permission.
    var distributedNotificationName: Notification.Name {
        Notification.Name("com.johnny4young.gancho.menu-bar-command.\(rawValue)")
    }

    static func command(
        forDistributedNotification name: Notification.Name
    )
        -> GanchoMenuBarCommand?
    {
        allCases.first { $0.distributedNotificationName == name }
    }

    func postDistributed(token: String) {
        DistributedNotificationCenter.default().postNotificationName(
            distributedNotificationName,
            object: token,
            userInfo: nil,
            options: [.deliverImmediately])
    }

    /// The helper's own menu, shown only when the app doesn't answer a click:
    /// commands, no clips. State-dependent commands keep neutral titles there.
    static let helperMenuSections: [[GanchoMenuBarCommand]] = [
        [.openPanel, .library, .copyScreenText],
        [.toggleCapture, .togglePrivateMode, .ignoreNextCopy],
        [.settings, .privacyCenter, .welcome, .wrapped],
        [.quit]
    ]

    var title: String {
        switch self {
        case .copyScreenText: String(localized: "Copy text from screen")
        case .library: String(localized: "Library")
        case .openPanel: String(localized: "Open panel")
        case .toggleCapture: String(localized: "Pause or resume capture")
        case .togglePrivateMode: String(localized: "Private mode")
        case .ignoreNextCopy: String(localized: "Ignore next copy")
        case .settings: String(localized: "Settings…")
        case .welcome: String(localized: "Welcome to Gancho")
        case .privacyCenter: String(localized: "Privacy Center")
        case .wrapped: String(localized: "My Clipboard, Wrapped…")
        case .fixClipboardAccess: String(localized: "Fix clipboard access…")
        case .quit: String(localized: "Quit Gancho")
        }
    }

    var helperTitle: String {
        switch self {
        case .togglePrivateMode: String(localized: "Toggle Private Mode")
        case .copyScreenText, .library, .openPanel, .toggleCapture, .ignoreNextCopy, .settings,
            .welcome,
            .privacyCenter, .wrapped, .fixClipboardAccess, .quit:
            title
        }
    }

    /// Leading SF Symbol for the row, matching the design's menu icons.
    var iconSymbol: String {
        switch self {
        case .copyScreenText: "text.viewfinder"
        case .library: "books.vertical"
        case .openPanel: "macwindow"
        case .toggleCapture: "pause"
        case .togglePrivateMode: "eye.slash"
        case .ignoreNextCopy: "minus.circle"
        case .settings: "gearshape"
        case .welcome: "hand.wave"
        case .privacyCenter: "lock.shield"
        case .wrapped: "gift"
        case .fixClipboardAccess: "exclamationmark.triangle"
        case .quit: "power"
        }
    }

    var accessibilityIdentifier: String { "menu-bar-command-\(rawValue)" }

    var accessibilityLabel: String {
        switch self {
        case .copyScreenText: String(localized: "Copy text from screen")
        case .library: String(localized: "Open clipboard library")
        case .openPanel: String(localized: "Open clipboard panel")
        case .toggleCapture: String(localized: "Pause or resume clipboard capture")
        case .togglePrivateMode: String(localized: "Toggle private mode")
        case .ignoreNextCopy: String(localized: "Ignore the next clipboard copy")
        case .settings: String(localized: "Open settings")
        case .welcome: String(localized: "Open welcome")
        case .privacyCenter: String(localized: "Open privacy center")
        case .wrapped: String(localized: "Export clipboard wrapped")
        case .fixClipboardAccess: String(localized: "Open clipboard access settings")
        case .quit: String(localized: "Quit Gancho")
        }
    }

    /// Fixed key equivalents only. Open panel shows the user's recorded panel
    /// shortcut instead, applied by each menu from KeyboardShortcuts or the bridge.
    var keyEquivalent: String {
        switch self {
        case .settings: ","
        case .quit: "q"
        case .openPanel, .copyScreenText, .library, .toggleCapture, .togglePrivateMode,
            .ignoreNextCopy, .welcome, .privacyCenter, .wrapped, .fixClipboardAccess:
            ""
        }
    }

    var modifiers: NSEvent.ModifierFlags {
        switch self {
        case .settings, .quit: [.command]
        case .openPanel, .copyScreenText, .library, .toggleCapture, .togglePrivateMode,
            .ignoreNextCopy, .welcome, .privacyCenter, .wrapped, .fixClipboardAccess:
            []
        }
    }

    init?(deepLink url: URL) {
        guard url.scheme == "gancho", url.host?.lowercased() == "menu-bar" else {
            return nil
        }
        guard let rawValue = url.pathComponents.dropFirst().first else { return nil }
        self.init(rawValue: rawValue)
    }

    /// The command a deep link asks for, only when it carries `nonce`, so a
    /// forged gancho://menu-bar/... open from another app is ignored.
    static func authorized(_ url: URL, nonce: String) -> GanchoMenuBarCommand? {
        guard let command = GanchoMenuBarCommand(deepLink: url), token(in: url) == nonce else {
            return nil
        }
        return command
    }

    /// The nonce stamped onto a command deep link, if present.
    static func token(in url: URL) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == "token" }?
            .value
    }

    func title(captureIsRunning: Bool?) -> String {
        guard self == .toggleCapture, let captureIsRunning else {
            return title
        }
        return captureIsRunning
            ? String(localized: "Pause capture")
            : String(localized: "Resume capture")
    }
}

/// Content-free signals around the status-item menu. The helper asks the app
/// to show its menu; the app says when that menu opens and closes so the
/// helper can hold the button's highlight. Each carries only the nonce.
enum GanchoMenuBarSignal: String, CaseIterable {
    case showMenu
    case menuDidOpen
    case menuDidClose

    /// How long the app has to answer `showMenu` before the helper opens its
    /// own menu; the app drops requests older than this.
    static let menuAnswerTimeout: TimeInterval = 0.5

    var distributedNotificationName: Notification.Name {
        Notification.Name("com.johnny4young.gancho.menu-bar-signal.\(rawValue)")
    }

    func post(token: String) {
        DistributedNotificationCenter.default().postNotificationName(
            distributedNotificationName, object: token, userInfo: nil,
            options: [.deliverImmediately])
    }
}

extension MenuBarClick {
    init(event: NSEvent?) {
        let flags = event?.modifierFlags.intersection(.deviceIndependentFlagsMask) ?? []
        self.init(option: flags.contains(.option), shift: flags.contains(.shift))
    }

    /// The command a modifier click runs; nil opens the menu.
    var command: GanchoMenuBarCommand? {
        switch self {
        case .openMenu: nil
        case .toggleCapture: .toggleCapture
        case .ignoreNextCopy: .ignoreNextCopy
        }
    }
}

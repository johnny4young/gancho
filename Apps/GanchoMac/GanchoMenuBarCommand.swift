import AppKit
import Foundation

/// Shared command metadata for Gancho's menu-bar surfaces.
///
/// Vitrine keeps its command titles, shortcuts, symbols, and accessibility
/// identifiers in one enum so menus and equivalent controls cannot drift.
/// Gancho follows the same maintainability pattern here: the in-process
/// `NSStatusItem` fallback and the external paint-only helper both render this
/// command surface, while the main app remains the only process that performs
/// private clipboard work.
enum GanchoMenuBarCommand: String, CaseIterable {
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
    case showInDock
    case quit

    static let appTitle = String(localized: "Gancho")
    static let statusGlyph = "📎"
    static let statusItemLength: CGFloat = 32
    static let statusAccessibilityLabel = String(localized: "Gancho")

    /// Commands the helper can safely show without reading clipboard state.
    ///
    /// Recent clips stay only in the main app process so clipboard previews are
    /// never copied into the helper. State-dependent commands use neutral
    /// titles in the helper and stateful titles/checkmarks in the in-process
    /// fallback.
    static let helperMenuSections: [[GanchoMenuBarCommand]] = [
        [.openPanel, .library],
        [.toggleCapture, .togglePrivateMode, .ignoreNextCopy],
        [.settings, .privacyCenter, .welcome, .wrapped, .showInDock],
        [.quit],
    ]

    var title: String {
        switch self {
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
        case .showInDock: String(localized: "Show in Dock")
        case .quit: String(localized: "Quit Gancho")
        }
    }

    var helperTitle: String {
        switch self {
        case .togglePrivateMode: String(localized: "Toggle Private Mode")
        case .showInDock: String(localized: "Toggle Dock Icon")
        case .library, .openPanel, .toggleCapture, .ignoreNextCopy, .settings, .welcome,
            .privacyCenter, .wrapped, .fixClipboardAccess, .quit:
            title
        }
    }

    var accessibilityIdentifier: String { "menu-bar-command-\(rawValue)" }

    var accessibilityLabel: String {
        switch self {
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
        case .showInDock: String(localized: "Toggle Dock icon")
        case .quit: String(localized: "Quit Gancho")
        }
    }

    var keyEquivalent: String {
        switch self {
        case .openPanel: "v"
        case .settings: ","
        case .quit: "q"
        case .library, .toggleCapture, .togglePrivateMode, .ignoreNextCopy, .welcome,
            .privacyCenter, .wrapped, .fixClipboardAccess, .showInDock:
            ""
        }
    }

    var modifiers: NSEvent.ModifierFlags {
        switch self {
        case .openPanel: [.command, .shift]
        case .settings, .quit: [.command]
        case .library, .toggleCapture, .togglePrivateMode, .ignoreNextCopy, .welcome,
            .privacyCenter, .wrapped, .fixClipboardAccess, .showInDock:
            []
        }
    }

    /// The command deep link, stamped with the per-launch nonce so the app can
    /// reject forged `gancho://menu-bar/...` opens from other processes.
    func deepLinkURL(token: String) -> URL {
        var components = URLComponents()
        components.scheme = "gancho"
        components.host = "menu-bar"
        components.path = "/\(rawValue)"
        components.queryItems = [URLQueryItem(name: "token", value: token)]
        return components.url!
    }

    init?(deepLink url: URL) {
        guard url.scheme == "gancho", url.host?.lowercased() == "menu-bar" else {
            return nil
        }
        guard let rawValue = url.pathComponents.dropFirst().first else { return nil }
        self.init(rawValue: rawValue)
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

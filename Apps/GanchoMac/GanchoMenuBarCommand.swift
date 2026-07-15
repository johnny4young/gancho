import AppKit
import Foundation

/// Shared command metadata for Gancho's menu-bar surfaces.
///
/// Command titles, shortcuts, symbols, and accessibility identifiers live in
/// one enum so menus and equivalent controls cannot drift: the in-process
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

    /// Commands the helper can safely show without reading clipboard state.
    ///
    /// Recent clips stay only in the main app process so clipboard previews are
    /// never copied into the helper. State-dependent commands use neutral
    /// titles in the helper and stateful titles/checkmarks in the in-process
    /// fallback.
    static let helperMenuSections: [[GanchoMenuBarCommand]] = [
        [.openPanel, .library],
        [.toggleCapture, .togglePrivateMode, .ignoreNextCopy],
        [.settings, .privacyCenter, .welcome, .wrapped],
        [.quit]
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
        case .quit: String(localized: "Quit Gancho")
        }
    }

    var helperTitle: String {
        switch self {
        case .togglePrivateMode: String(localized: "Toggle Private Mode")
        case .library, .openPanel, .toggleCapture, .ignoreNextCopy, .settings, .welcome,
            .privacyCenter, .wrapped, .fixClipboardAccess, .quit:
            title
        }
    }

    /// Leading SF Symbol for the row, matching the design's menu icons.
    var iconSymbol: String {
        switch self {
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

    var keyEquivalent: String {
        switch self {
        case .openPanel: "v"
        case .settings: ","
        case .quit: "q"
        case .library, .toggleCapture, .togglePrivateMode, .ignoreNextCopy, .welcome,
            .privacyCenter, .wrapped, .fixClipboardAccess:
            ""
        }
    }

    var modifiers: NSEvent.ModifierFlags {
        switch self {
        case .openPanel: [.command, .shift]
        case .settings, .quit: [.command]
        case .library, .toggleCapture, .togglePrivateMode, .ignoreNextCopy, .welcome,
            .privacyCenter, .wrapped, .fixClipboardAccess:
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

/// The menu-bar status item's icon. Carried content-free across the App Group
/// bridge as its `rawValue` (a state identifier — never clipboard data); the
/// helper process and the in-process fallback both render it. `.active` is
/// gancho's hook mark; the exception states use SF Symbols so a problem reads
/// at a glance.
enum MenuBarStatusIcon: String {
    case active
    case paused
    case stopped
    case denied

    /// A template image sized for the menu bar. macOS tints template images
    /// automatically (white on dark bars, dark on light), so the mark is never
    /// baked with a color — matching the design's menu-bar template guidance.
    func templateImage() -> NSImage {
        switch self {
        case .active: Self.hookImage
        case .paused: Self.symbol("pause.circle")
        case .stopped: Self.symbol("stop.circle")
        case .denied: Self.symbol("exclamationmark.triangle.fill")
        }
    }

    /// A small filled status dot for the menu header — green when capturing,
    /// gray when paused, red when access is denied. Intentionally colored (not a
    /// template): a glanceable state cue beside the localized status text.
    func statusDot() -> NSImage {
        let color: NSColor
        switch self {
        case .active: color = .systemGreen
        case .paused, .stopped: color = .systemGray
        case .denied: color = .systemRed
        }
        let side: CGFloat = 10
        return NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            color.setFill()
            NSBezierPath(ovalIn: rect.insetBy(dx: 1, dy: 1)).fill()
            return true
        }
    }

    private static func symbol(_ name: String) -> NSImage {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil) ?? NSImage()
        image.isTemplate = true
        return image
    }

    /// gancho's hook, drawn from the design's SVG path (`assets/gancho-mark.svg`,
    /// viewBox 0 0 96 96) converted to AppKit's y-up space, with the menu-bar
    /// variant's bolder strokes (13 / 9) so it holds at ~18 pt. Verified against
    /// the design SVG by rendering both to PNG.
    private static let hookImage: NSImage = {
        let side: CGFloat = 18
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            let transform = NSAffineTransform()
            transform.scale(by: side / 96)
            transform.concat()
            NSColor.black.set()

            let hook = NSBezierPath()
            hook.lineWidth = 13
            hook.lineCapStyle = .round
            hook.lineJoinStyle = .round
            hook.move(to: NSPoint(x: 50, y: 64))  // SVG (50,32) — top of the stem
            hook.line(to: NSPoint(x: 50, y: 39))  // SVG (50,57) — bottom of the stem
            hook.appendArc(
                withCenter: NSPoint(x: 42.5, y: 26.01), radius: 15,
                startAngle: 60, endAngle: 120, clockwise: true)  // the bottom curl
            hook.line(to: NSPoint(x: 31.5, y: 48.5))  // SVG (31.5,47.5) — the barb
            hook.stroke()

            let eye = NSBezierPath(ovalIn: NSRect(x: 42, y: 64, width: 16, height: 16))
            eye.lineWidth = 9
            eye.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }()
}

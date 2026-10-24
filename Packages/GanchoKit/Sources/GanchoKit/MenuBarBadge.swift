import Foundation

/// The one coloured badge on the menu-bar hook. Content-free state, so it can
/// cross to the menu-bar helper as `bridgeValue`; the hook alone means capturing.
public enum MenuBarBadge: Equatable, Sendable {
    case denied
    case paused
    case privateMode
    case ignoreNext
    case stack(Int)

    /// Denied, then paused (manual, screen share or lock), then Private Mode,
    /// then an armed ignore-next, then a waiting paste stack.
    public static func resolve(
        denied: Bool, paused: Bool, privateMode: Bool, ignoresNextCopy: Bool, stackCount: Int
    ) -> MenuBarBadge? {
        if denied { return .denied }
        if paused { return .paused }
        if privateMode { return .privateMode }
        if ignoresNextCopy { return .ignoreNext }
        return stackCount > 0 ? .stack(stackCount) : nil
    }

    /// The badge's single character; a stack past nine reads "9+".
    public var glyph: String {
        switch self {
        case .denied: "!"
        case .paused: "‖"
        case .privateMode: "/"
        case .ignoreNext: "−"
        case .stack(let count): count > 9 ? "9+" : "\(count)"
        }
    }

    public var bridgeValue: String {
        switch self {
        case .denied: "denied"
        case .paused: "paused"
        case .privateMode: "private"
        case .ignoreNext: "ignore-next"
        case .stack(let count): "stack:\(count)"
        }
    }

    public init?(bridgeValue: String) {
        switch bridgeValue {
        case "denied": self = .denied
        case "paused": self = .paused
        case "private": self = .privateMode
        case "ignore-next": self = .ignoreNext
        default:
            guard bridgeValue.hasPrefix("stack:"),
                let count = Int(bridgeValue.dropFirst("stack:".count)), count > 0
            else { return nil }
            self = .stack(count)
        }
    }
}

/// What a click on the status item does: ⌥ pauses or resumes capture, ⌥⇧
/// ignores the next copy, anything else opens the menu.
public enum MenuBarClick: Equatable, Sendable {
    case openMenu
    case toggleCapture
    case ignoreNextCopy

    public init(option: Bool, shift: Bool) {
        self = option ? (shift ? .ignoreNextCopy : .toggleCapture) : .openMenu
    }
}

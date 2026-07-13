import GanchoKit
import SwiftUI

/// The only color tokens that can be persisted for a board. Keeping this list
/// closed prevents unreadable arbitrary colors while preserving stable values
/// across app versions and devices.
public enum BoardIdentityColor: String, CaseIterable, Identifiable, Sendable {
    case blue = "#2E70D1"
    case orange = "#F08C08"
    case teal = "#17999E"
    case pink = "#D4547D"
    case purple = "#874AB8"
    case brown = "#996633"

    public var id: String { rawValue }

    public var color: Color {
        // Every raw value is a compile-time six-digit RGB token.
        Color(hexString: rawValue) ?? .secondary
    }

    public var name: LocalizedStringKey {
        switch self {
        case .blue: "Blue"
        case .orange: "Orange"
        case .teal: "Teal"
        case .pink: "Pink"
        case .purple: "Purple"
        case .brown: "Brown"
        }
    }

    /// Accept tokens case-insensitively, but always return the canonical value
    /// written by the current app. Unknown or legacy arbitrary colors fall back
    /// to the board's automatic identity instead of reaching the renderer.
    public static func canonicalToken(_ token: String?) -> String? {
        guard let token else { return nil }
        return Self(rawValue: token.uppercased())?.rawValue
    }
}

/// A deliberately small emoji vocabulary that remains comfortable with
/// keyboard, pointer, VoiceOver, and Switch Control. The persisted value is the
/// emoji itself, so sync stays independent from localized display names.
public enum BoardIdentityEmoji: String, CaseIterable, Identifiable, Sendable {
    case briefcase = "💼"
    case books = "📚"
    case art = "🎨"
    case travel = "✈️"
    case home = "🏠"
    case idea = "💡"
    case heart = "❤️"
    case star = "⭐️"
    case pin = "📌"
    case done = "✅"
    case rocket = "🚀"
    case shopping = "🛒"

    public var id: String { rawValue }

    public var name: LocalizedStringKey {
        switch self {
        case .briefcase: "Briefcase"
        case .books: "Books"
        case .art: "Art"
        case .travel: "Travel"
        case .home: "Home"
        case .idea: "Idea"
        case .heart: "Heart"
        case .star: "Star"
        case .pin: "Pin"
        case .done: "Done"
        case .rocket: "Rocket"
        case .shopping: "Shopping"
        }
    }

    public static func canonicalToken(_ token: String?) -> String? {
        guard let token else { return nil }
        return Self(rawValue: token)?.rawValue
    }
}

/// One quiet identity color per board — a spine/dot accent over neutral cards,
/// never a background wash (green stays the app accent). A user override wins;
/// otherwise the board's id provides a stable automatic choice.
public enum BoardColors {
    /// Stable identity color. The built-in Favorites board keeps the warm
    /// "favorite" hue; user boards prefer a valid persisted palette token and
    /// otherwise map by a fixed byte of their UUID.
    public static func color(for board: Pinboard) -> Color {
        guard !board.isSystem else { return GanchoTokens.Palette.warning }
        return option(for: board).color
    }

    /// The effective closed-palette option, exposed so the editor preview and
    /// tests use exactly the same automatic fallback as production rendering.
    public static func option(for board: Pinboard) -> BoardIdentityColor {
        if let token = BoardIdentityColor.canonicalToken(board.colorHex),
            let selected = BoardIdentityColor(rawValue: token)
        {
            return selected
        }
        let options = BoardIdentityColor.allCases
        return options[Int(board.id.uuid.0) % options.count]
    }
}

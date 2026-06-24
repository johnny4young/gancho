import GanchoKit
import SwiftUI

/// One quiet identity color per board — a spine/dot accent over neutral cards,
/// never a background wash (green stays the app accent). Derived from the
/// board's id so it is stable across launches without a stored color field;
/// a future user-chosen "Recolor" can persist an override on top.
public enum BoardColors {
    /// Muted, distinguishable hues — none of them the app's green accent.
    private static let palette: [Color] = [
        Color(red: 0.18, green: 0.44, blue: 0.82),  // blue
        Color(red: 0.94, green: 0.55, blue: 0.03),  // amber
        Color(red: 0.09, green: 0.60, blue: 0.62),  // teal
        Color(red: 0.83, green: 0.33, blue: 0.49),  // pink
        Color(red: 0.53, green: 0.29, blue: 0.72),  // purple
        Color(red: 0.60, green: 0.40, blue: 0.20),  // brown
    ]

    /// Stable identity color. The built-in Favorites board keeps the warm
    /// "favorite" hue; user boards map by a fixed byte of their UUID.
    public static func color(for board: Pinboard) -> Color {
        guard !board.isSystem else { return GanchoTokens.Palette.warning }
        return palette[Int(board.id.uuid.0) % palette.count]
    }
}

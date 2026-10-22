import CoreGraphics
import GanchoKit
import SwiftUI

/// Text scaling for Gancho's history panel: a multiplier over the panel's own
/// text styles (`PanelTextStyle`), because macOS SwiftUI does not scale text
/// through Dynamic Type.
public enum PanelTextSize: String, CaseIterable, Identifiable, Sendable {
    public static let storageKey = "panel-text-size"

    case small
    case standard
    case large

    public var id: String { rawValue }

    public static func resolved(_ rawValue: String?) -> Self {
        rawValue.flatMap(Self.init(rawValue:)) ?? .standard
    }
}

/// Useful starting sizes for the panel. Manual edge resizing remains available
/// and is remembered; presets are shortcuts, not modes that lock the window.
public enum PanelSizePreset: String, CaseIterable, Identifiable, Sendable {
    case compact
    case standard
    case large

    public var id: String { rawValue }

    public var contentSize: CGSize {
        switch self {
        case .compact: CGSize(width: 760, height: 480)
        case .standard: CGSize(width: 864, height: 540)
        case .large: CGSize(width: 1_080, height: 680)
        }
    }

    /// The preset a remembered size came from; nil after a manual resize.
    nonisolated public static func matching(_ size: CGSize) -> Self? {
        allCases.first {
            abs($0.contentSize.width - size.width) <= 1
                && abs($0.contentSize.height - size.height) <= 1
        }
    }
}

/// Whether the panel lets the desktop show through. Off by default: a solid
/// panel keeps clips legible over any wallpaper or window.
public enum PanelTranslucency {
    public static let storageKey = "panel-translucent-background"

    nonisolated public static func isEnabled(in defaults: UserDefaults) -> Bool {
        defaults.bool(forKey: storageKey)
    }
}

/// The optional ambient wash behind the peek: a faint field of the selected
/// clip's colour. Off by default; Settings owns the toggle.
public enum PanelAmbientTint {
    public static let storageKey = "panel-ambient-tint"

    /// Legibility first: no wash when the user reduced transparency or asked
    /// for more contrast, whatever the toggle says.
    nonisolated public static func isShown(
        enabled: Bool, reduceTransparency: Bool, increasedContrast: Bool
    ) -> Bool {
        enabled && !reduceTransparency && !increasedContrast
    }

    /// The wash's peak strength: 7 % in dark, 10 % in light, where a tint
    /// needs a little more colour to register on a pale surface.
    nonisolated public static func opacity(dark: Bool) -> Double {
        dark ? 0.07 : 0.10
    }

    /// A masked clip or Private Mode gets no wash at all: an image's own
    /// colour, or even the kind's tint, would hint at what the mask hides.
    nonisolated public static func washes(masked: Bool, privateMode: Bool) -> Bool {
        !masked && !privateMode
    }
}

/// How the history renders: the keyboard list, or a gallery of cards for
/// visual browsing. ⌘G toggles; the choice is remembered.
public enum PanelLayout: String, CaseIterable, Sendable {
    public static let storageKey = "panel-layout"

    case list
    case gallery

    public var toggled: PanelLayout { self == .list ? .gallery : .list }

    public static func resolved(_ rawValue: String?) -> PanelLayout {
        rawValue.flatMap(Self.init(rawValue:)) ?? .list
    }

    /// Cards want about 168 pt each; never fewer than two across.
    nonisolated public static func galleryColumns(forWidth width: CGFloat) -> Int {
        max(2, Int(width / 168))
    }
}

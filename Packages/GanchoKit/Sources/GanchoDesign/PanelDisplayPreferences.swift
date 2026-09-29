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
}

/// The optional ambient wash behind the panel: a faint field of the selected
/// clip's colour under the list and the peek. Off by default; Settings owns
/// the toggle.
public enum PanelAmbientTint {
    public static let storageKey = "panel-ambient-tint"

    /// Legibility first: no wash when the user reduced transparency or asked
    /// for more contrast, whatever the toggle says.
    nonisolated public static func isShown(
        enabled: Bool, reduceTransparency: Bool, increasedContrast: Bool
    ) -> Bool {
        enabled && !reduceTransparency && !increasedContrast
    }

    /// Wash strength per appearance: dark glass carries a little more colour
    /// before it reads as a tint.
    nonisolated public static func opacity(dark: Bool) -> Double {
        dark ? 0.22 : 0.14
    }

    /// Whether the wash may take an image's own colour. Only while that image
    /// is actually shown: a sensitive image or Private Mode masks the preview,
    /// and a content-derived colour would hint at what the mask hides. The
    /// kind's tint is the fallback either way.
    nonisolated public static func usesAccent(
        kind: ClipContentKind, isSensitive: Bool, previewsHidden: Bool
    ) -> Bool {
        kind == .image && !isSensitive && !previewsHidden
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

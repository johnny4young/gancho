import CoreGraphics
import GanchoKit
import SwiftUI

/// Semantic text scaling for Gancho's history panel.
///
/// The setting intentionally maps to Dynamic Type rather than fixed point
/// sizes, so every existing semantic style (`body`, `caption`, `headline`, …)
/// keeps its hierarchy and accessibility behavior.
public enum PanelTextSize: String, CaseIterable, Identifiable, Sendable {
    public static let storageKey = "panel-text-size"

    case small
    case standard
    case large

    public var id: String { rawValue }

    public var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .small: .medium
        case .standard: .large
        case .large: .xLarge
        }
    }

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

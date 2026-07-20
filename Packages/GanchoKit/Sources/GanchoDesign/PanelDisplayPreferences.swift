import CoreGraphics
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

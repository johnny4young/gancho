import SwiftUI

#if canImport(AppKit)
    import AppKit
    private typealias PlatformFont = NSFont
#else
    import UIKit
    private typealias PlatformFont = UIFont
#endif

/// The panel's text styles, set in the bundled faces. macOS SwiftUI does not
/// scale text through `dynamicTypeSize`, so on the Mac each style is sized from
/// the system's own point size times `panelTypeScale`; iOS keeps Dynamic Type.
public enum PanelTextStyle: Sendable, CaseIterable {
    case title2, title3, headline, body, callout, subheadline, footnote, caption, caption2

    /// The system's current point size for this style.
    public var baseSize: CGFloat {
        PlatformFont.preferredFont(forTextStyle: platformStyle).pointSize
    }

    public var defaultWeight: Font.Weight {
        self == .headline ? .semibold : .regular
    }

    #if os(iOS)
        /// The style's size at the default Dynamic Type setting, which a custom
        /// face scales from.
        var defaultSize: CGFloat { Self.defaultSizes[self] ?? baseSize }

        private static let defaultSizes: [PanelTextStyle: CGFloat] = {
            let traits = UITraitCollection(preferredContentSizeCategory: .large)
            return Dictionary(
                uniqueKeysWithValues: allCases.map {
                    (
                        $0,
                        PlatformFont.preferredFont(
                            forTextStyle: $0.platformStyle, compatibleWith: traits
                        ).pointSize
                    )
                })
        }()
    #endif

    var textStyle: Font.TextStyle {
        switch self {
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .body: .body
        case .callout: .callout
        case .subheadline: .subheadline
        case .footnote: .footnote
        case .caption: .caption
        case .caption2: .caption2
        }
    }

    private var platformStyle: PlatformFont.TextStyle {
        switch self {
        case .title2: .title2
        case .title3: .title3
        case .headline: .headline
        case .body: .body
        case .callout: .callout
        case .subheadline: .subheadline
        case .footnote: .footnote
        case .caption: .caption1
        case .caption2: .caption2
        }
    }
}

extension EnvironmentValues {
    /// Multiplier for the panel's text and the metrics that follow it; the
    /// Text size preference sets it at the panel root.
    @Entry public var panelTypeScale: CGFloat = 1
}

extension PanelTextSize {
    public var scale: CGFloat {
        switch self {
        case .small: 0.9
        case .standard: 1
        case .large: 1.15
        }
    }
}

private struct PanelFontModifier: ViewModifier {
    @Environment(\.panelTypeScale) private var scale
    let style: PanelTextStyle?
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    let digits: Bool

    func body(content: Content) -> some View {
        content.font(digits ? font.monospacedDigit() : font)
    }

    private var font: Font {
        #if os(iOS)
            if let style {
                return GanchoType.font(
                    design: design, size: style.defaultSize, weight: weight,
                    relativeTo: style.textStyle)
            }
        #endif
        return GanchoType.font(
            design: design, size: (style?.baseSize ?? size) * scale, weight: weight)
    }
}

extension View {
    /// A panel text style at the current type scale.
    public func panelFont(
        _ style: PanelTextStyle, _ weight: Font.Weight? = nil, design: Font.Design = .default,
        digits: Bool = false
    ) -> some View {
        modifier(
            PanelFontModifier(
                style: style, size: 0, weight: weight ?? style.defaultWeight, design: design,
                digits: digits))
    }

    /// A fixed base size (glyphs, monograms, empty-state symbols) at the
    /// current type scale.
    public func panelFont(
        size: CGFloat, _ weight: Font.Weight = .regular, design: Font.Design = .default
    ) -> some View {
        modifier(
            PanelFontModifier(style: nil, size: size, weight: weight, design: design, digits: false)
        )
    }
}

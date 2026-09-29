import SwiftUI

/// The panel's text styles as point sizes. macOS SwiftUI does not scale text
/// with `dynamicTypeSize`, so the panel scales its own styles from these bases
/// through `panelTypeScale`; the sizes mirror the macOS system text styles.
public enum PanelTextStyle: Sendable, CaseIterable {
    case title2, title3, headline, body, callout, subheadline, footnote, caption, caption2

    public var baseSize: CGFloat {
        switch self {
        case .title2: 17
        case .title3: 15
        case .headline, .body: 13
        case .callout: 12
        case .subheadline: 11
        case .footnote, .caption, .caption2: 10
        }
    }

    public var defaultWeight: Font.Weight {
        self == .headline ? .semibold : .regular
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
    let size: CGFloat
    let weight: Font.Weight
    let design: Font.Design
    let digits: Bool

    func body(content: Content) -> some View {
        let font = Font.system(size: size * scale, weight: weight, design: design)
        content.font(digits ? font.monospacedDigit() : font)
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
                size: style.baseSize, weight: weight ?? style.defaultWeight, design: design,
                digits: digits))
    }

    /// A fixed base size (glyphs, monograms, empty-state symbols) at the
    /// current type scale.
    public func panelFont(
        size: CGFloat, _ weight: Font.Weight = .regular, design: Font.Design = .default
    ) -> some View {
        modifier(PanelFontModifier(size: size, weight: weight, design: design, digits: false))
    }
}

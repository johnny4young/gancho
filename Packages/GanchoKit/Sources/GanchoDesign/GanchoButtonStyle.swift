import SwiftUI

/// The shared state rule: hover and pressed move a fill's lightness 8 % and
/// 16 % (darker in light, lighter in dark), disabled is 40 % opacity with no
/// shadow, and keyboard focus draws a 2 pt ring in the control's hue 2 pt out.
public enum ButtonStates {
    public static let hoverStep = 0.08
    public static let pressedStep = 0.16
    public static let disabledOpacity = 0.4
}

/// One saturated control per surface: `primary` is the verb Return runs, and
/// the only accent fill. Secondary is surface + hairline, tertiary is quiet
/// ink with a wash on hover, destructive is red text (a red fill belongs only
/// in a confirmation).
public enum GanchoButtonRole: Sendable {
    case primary, secondary, tertiary, neutral, destructive
}

public struct GanchoButtonStyle: ButtonStyle {
    let role: GanchoButtonRole

    public init(_ role: GanchoButtonRole) { self.role = role }

    public func makeBody(configuration: Configuration) -> some View {
        // A destructive button stays destructive under a container-wide style.
        GanchoButtonBody(
            role: configuration.role == .destructive ? .destructive : role,
            configuration: configuration)
    }
}

extension View {
    /// Applies the shared button style to one control and replaces the system
    /// focus effect with the style's own ring. Applied to a container instead
    /// (`.buttonStyle(GanchoButtonStyle(.secondary))`), the system ring stays.
    public func ganchoButtonStyle(_ role: GanchoButtonRole) -> some View {
        buttonStyle(GanchoButtonStyle(role))
            .environment(\.ganchoDrawsFocusRing, true)
            .focusEffectDisabled()
    }
}

extension EnvironmentValues {
    @Entry var ganchoDrawsFocusRing = false
}

extension View {
    /// A borderless text or icon button in full ink (a borderless button
    /// otherwise inherits the muted control tint).
    public func ganchoTextButton() -> some View {
        buttonStyle(.borderless).foregroundStyle(GanchoTokens.Palette.ink)
    }

    /// Tints a control that paints its own label in the tint (a borderless
    /// menu, a button-style toggle) with full ink instead.
    public func ganchoInkTint() -> some View { tint(GanchoTokens.Palette.ink) }

    /// The primary verb drawn on a custom label (a full-width sheet button, a
    /// widget, a dock): the accent fill and its ink. `step` is the hover or
    /// pressed fraction from `ButtonStates`.
    public func ganchoPrimaryVerb(in shape: some Shape, step: Double = 0) -> some View {
        modifier(PrimaryVerbFill(shape: AnyShape(shape), step: step))
    }
}

private struct PrimaryVerbFill: ViewModifier {
    let shape: AnyShape
    let step: Double
    @Environment(\.self) private var environment

    func body(content: Content) -> some View {
        let fill = Color(
            Contrast.stepped(
                GanchoTokens.Palette.accent.resolve(in: environment), by: step,
                lighter: environment.colorScheme == .dark))
        content
            .foregroundStyle(ContrastingForeground(on: fill))
            .background(fill, in: shape)
    }
}

#if canImport(UIKit)
    extension GanchoTokens {
        /// The primary verb's colours for a UIKit control the system draws.
        public enum PrimaryVerb {
            public static var uiFill: UIColor { UIColor(Palette.accent) }
            public static var uiInk: UIColor { UIColor(Color(ColorPair.onAccent.resolved(.light))) }
        }
    }
#endif

private struct GanchoButtonBody: View {
    let role: GanchoButtonRole
    let configuration: ButtonStyleConfiguration

    @Environment(\.self) private var environment
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.ganchoDrawsFocusRing) private var drawsFocusRing
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovering = false

    private let radius = GanchoTokens.Radius.md

    var body: some View {
        let fill = fillColor
        configuration.label
            .fontWeight(.semibold)
            .lineLimit(1)
            .padding(.horizontal, GanchoTokens.Spacing.sm)
            .frame(minHeight: GanchoTokens.HitTarget.button)
            .foregroundStyle(ink(on: fill))
            .background(fill ?? .clear, in: shape)
            .overlay {
                if role == .secondary {
                    shape.strokeBorder(
                        .primary.opacity(0.1), lineWidth: GanchoTokens.Stroke.hairline)
                }
            }
            .shadow(color: shadowColor(fill), radius: 6, y: 4)
            .overlay {
                if drawsFocusRing, isFocused {
                    RoundedRectangle(cornerRadius: radius + 4, style: .continuous)
                        .strokeBorder(ringColor, lineWidth: GanchoTokens.Stroke.focus)
                        .padding(-(GanchoTokens.Stroke.focus * 2))
                }
            }
            .contentShape(shape)
            .opacity(isEnabled ? 1 : ButtonStates.disabledOpacity)
            #if os(macOS)
                .onHover { isHovering = $0 }
            #endif
            .animation(GanchoMotion.quick(reduceMotion: reduceMotion), value: isHovering)
            .animation(
                GanchoMotion.quick(reduceMotion: reduceMotion), value: configuration.isPressed
            )
            .scaleEffect(
                role == .primary && configuration.isPressed
                    ? GanchoMotion.pressScale(reduceMotion: reduceMotion) : 1
            )
            .animation(GanchoMotion.press, value: configuration.isPressed)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
    }

    private var step: Double {
        guard isEnabled else { return 0 }
        if configuration.isPressed { return ButtonStates.pressedStep }
        return isHovering ? ButtonStates.hoverStep : 0
    }

    private func stepped(_ color: Color) -> Color {
        Color(
            Contrast.stepped(
                color.resolve(in: environment), by: step, lighter: colorScheme == .dark))
    }

    private var fillColor: Color? {
        switch role {
        case .primary:
            return stepped(GanchoTokens.Palette.accent)
        case .secondary:
            return stepped(GanchoTokens.Palette.surface(.control))
        case .tertiary, .neutral:
            guard step > 0 else { return nil }
            return Color.primary.opacity(configuration.isPressed ? 0.09 : 0.05)
        case .destructive:
            guard step > 0 else { return nil }
            return GanchoTokens.Palette.danger.opacity(configuration.isPressed ? 0.15 : 0.08)
        }
    }

    private func ink(on fill: Color?) -> AnyShapeStyle {
        switch role {
        case .primary: AnyShapeStyle(ContrastingForeground(on: fill ?? .clear))
        case .secondary, .neutral: AnyShapeStyle(.primary)
        case .tertiary: AnyShapeStyle(GanchoTokens.Palette.ink2)
        case .destructive: AnyShapeStyle(GanchoTokens.Palette.danger)
        }
    }

    private var ringColor: AnyShapeStyle {
        role == .destructive
            ? AnyShapeStyle(GanchoTokens.Palette.danger)
            : AnyShapeStyle(GanchoTokens.Palette.ink)
    }

    /// Only the primary fill casts a coloured shadow, and never in dark or
    /// when disabled.
    private func shadowColor(_ fill: Color?) -> Color {
        guard role == .primary, isEnabled, colorScheme == .light, let fill else { return .clear }
        return fill.opacity(0.28)
    }
}

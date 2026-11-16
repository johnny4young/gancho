import SwiftUI

#if canImport(AppKit)
    import AppKit
#elseif canImport(UIKit)
    import UIKit
#endif

/// Semantic color tokens. gancho is neutral graphite with ONE accent, and the
/// accent means "Return does this": it is internal to this module and reaches
/// the apps only through the caret, the Return key cap, the primary verb and
/// the live-capture dot. Everything else is ink on a neutral wash.
extension GanchoTokens {
    public enum Palette {
        // MARK: Brand mark

        /// The green of the app icon and brand mark. Never an interface tint.
        public static let brandGreen = ColorPair.brand.color

        /// Deeper green for the region-selection cursor, not a global brand override.
        /// A cursor crosses other apps' light and dark content independently of our appearance.
        public static let regionSelectionCursor = Color(
            .sRGB, red: 0x2E / 255, green: 0xAD / 255, blue: 0x50 / 255, opacity: 1)

        // MARK: Neutral graphite

        /// A translucent resting fill for chips, key caps and tiles, on any
        /// surface. `surface(.control)` is the opaque level controls sit on.
        public static let controlFill = ColorPair.controlFill.color
        /// The selected row, tab, chip or pill. Selection is never the accent.
        public static let selectionWash = ColorPair.selection.color
        /// Primary text and glyphs, and the fill of an inverse surface.
        public static let ink = ColorPair.ink.color
        /// Secondary text, links and quiet glyphs.
        public static let ink2 = ColorPair.ink2.color
        /// Captions, counts and placeholders.
        public static let ink3 = ColorPair.ink3.color
        public static let hairline = ColorPair.hairline.color

        public static var inverseFill: Color { ink }
        public static let inverseText = ColorPair.panel.color

        /// Tint for system controls (switches, progress, links). Mid graphite
        /// in dark: full ink would hide a switch's white knob.
        public static let controlTint = ColorPair.controlTint.color

        // MARK: Semantic status roles

        /// Success and "Synced" render neutral; pair it with a checkmark.
        public static var success: Color { ink2 }

        /// Warning status (sync paused, permission missing) — `--warning`.
        public static let warning = ColorPair.warning.color

        /// Delete, access denied and a secret's last minute. Reads as text on
        /// every surface.
        public static let danger = ColorPair.danger.color

        /// Indigo: Private Mode (never read as a pause or a failure) and search filter tokens.
        public static let indigo = ColorPair.indigo.color

        /// Agent activity: MCP clients reading or organizing clips.
        public static let agent = ColorPair.agent.color

        /// Warning amber as text or a status glyph; the raw amber is 2.2:1 on white.
        public static var warningInk: ReadableInk { ReadableInk(base: warning) }

        // MARK: Accent — follows the OS Theme color, lure lime by default

        /// Whether gancho uses its own lime. macOS writes `AppleAccentColor`
        /// to the global domain only when the user picks a specific accent in
        /// System Settings; under "Multicolor" (the default) the key is absent.
        public static func usesBrandAccent(appleAccentColorKeyPresent present: Bool) -> Bool {
            !present
        }

        /// Read once: a system-accent change is picked up on the next launch.
        static let accentIsBrand: Bool = {
            #if DEBUG
                // Design snapshots pin the brand accent whatever this Mac's Theme colour is.
                if CommandLine.arguments.contains("-ui-test-brand-accent") { return true }
            #endif
            #if canImport(AppKit)
                return usesBrandAccent(
                    appleAccentColorKeyPresent: UserDefaults.standard.object(
                        forKey: "AppleAccentColor") != nil)
            #else
                return true
            #endif
        }()

        /// The accent as a fill.
        static var accent: Color { accentIsBrand ? lime : systemAccent }

        private static let lime = ColorPair.accent.color

        #if canImport(AppKit)
            private static var systemAccent: Color { Color(nsColor: .controlAccentColor) }
        #else
            // iOS / iPadOS expose no per-app system accent.
            private static var systemAccent: Color { lime }
        #endif

        /// The accent as text or a stroke: the caret and the live dot.
        static var accentText: AccentText { AccentText() }

        // MARK: Surfaces

        /// Opaque surface of a level. Dark uses fixed greys so text contrast
        /// is predictable on the Mac; light keeps the system backgrounds.
        public static func surface(_ level: GanchoTokens.SurfaceLevel) -> Color {
            #if os(macOS)
                switch level {
                case .panel:
                    return dynamic(system: .windowBackgroundColor, dark: (0x1C, 0x1C, 0x1E))
                case .card:
                    return dynamic(system: .controlBackgroundColor, dark: (0x2C, 0x2C, 0x2E))
                case .control:
                    return dynamic(system: .controlColor, dark: (0x3A, 0x3A, 0x3C))
                }
            #else
                switch level {
                case .panel: return Color(uiColor: .systemBackground)
                case .card: return Color(uiColor: .secondarySystemBackground)
                case .control: return Color(uiColor: .tertiarySystemBackground)
                }
            #endif
        }

        // MARK: Dynamic color helper

        #if os(macOS)
            /// The system colour in light, a fixed sRGB grey in dark.
            private static func dynamic(system: NSColor, dark: (Int, Int, Int)) -> Color {
                Color(
                    nsColor: NSColor(name: nil) { appearance in
                        guard appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua else {
                            return system
                        }
                        return NSColor(
                            srgbRed: CGFloat(dark.0) / 255, green: CGFloat(dark.1) / 255,
                            blue: CGFloat(dark.2) / 255, alpha: 1)
                    })
            }
        #endif

    }
}

extension GanchoTokens {
    /// Token colors for `GanchoSyntax`. The dark values are the design editor's
    /// palette; the light
    /// values are darker, legible variants of the same hues, so highlighting
    /// honours the app's Light/Dark choice — the code editor is an elevated
    /// surface, not a fixed-dark panel.
    public enum Syntax {
        /// (light, dark) sRGB byte triples for a token kind.
        static func triples(
            for kind: GanchoSyntax.TokenKind
        ) -> (light: (Int, Int, Int), dark: (Int, Int, Int)) {
            switch kind {
            case .keyword: return ((0xA3, 0x3E, 0xA3), (0xC6, 0x78, 0xDD))
            case .string: return ((0x2E, 0x7D, 0x32), (0x98, 0xC3, 0x79))
            case .comment: return ((0x8A, 0x8A, 0x8E), (0x5C, 0x66, 0x70))
            case .number: return ((0xB2, 0x50, 0x00), (0xD1, 0x9A, 0x66))
            case .placeholder: return ((0xB2, 0x6A, 0x00), (0xE5, 0xC0, 0x7B))
            }
        }

        /// SwiftUI color for a token kind (used by the floating-panel preview).
        public static func color(for kind: GanchoSyntax.TokenKind) -> Color {
            let t = triples(for: kind)
            return ColorPair(light: t.light, dark: t.dark).color
        }

        /// `source` with every `GanchoSyntax` token tinted. Callers own any size cap.
        public static func highlighted(_ source: String) -> AttributedString {
            var attributed = AttributedString(source)
            for token in GanchoSyntax.tokens(in: source) {
                let lower = source.distance(from: source.startIndex, to: token.range.lowerBound)
                let upper = source.distance(from: source.startIndex, to: token.range.upperBound)
                let lo = attributed.index(attributed.startIndex, offsetByCharacters: lower)
                let hi = attributed.index(attributed.startIndex, offsetByCharacters: upper)
                attributed[lo..<hi].foregroundColor = color(for: token.kind)
            }
            return attributed
        }

        #if canImport(AppKit)
            /// Appearance-dynamic `NSColor` for a token kind (used by the AppKit
            /// Library editor so the tint updates live on a theme switch).
            public static func nsColor(for kind: GanchoSyntax.TokenKind) -> NSColor {
                let t = triples(for: kind)
                return ColorPair(light: t.light, dark: t.dark).nsColor
            }

            /// The editor's elevated code surface — near-black on dark (the
            /// design's `#15191e`), a soft off-white on light.
            public static var editorSurface: NSColor {
                ColorPair(light: (0xF6, 0xF7, 0xF9), dark: (0x15, 0x19, 0x1E)).nsColor
            }

            /// The line-number gutter background — a shade deeper than the code
            /// surface on each appearance.
            public static var editorGutter: NSColor {
                ColorPair(light: (0xEC, 0xEE, 0xF1), dark: (0x10, 0x14, 0x18)).nsColor
            }

            /// The gutter's line-number text — muted on both appearances.
            public static var editorGutterText: NSColor {
                ColorPair(light: (0xA0, 0xA4, 0xAA), dark: (0x4B, 0x55, 0x60)).nsColor
            }
        #endif
    }
}

extension View {
    /// Tints system controls with the neutral control tint and applies the app
    /// locale. Applied at every SwiftUI root (windows, panel, settings).
    public func ganchoTinted() -> some View {
        tint(GanchoTokens.Palette.controlTint)
            .modifier(AppLocaleModifier())
    }
}

/// The accent as text or a stroke, legible in the appearance it renders in.
struct AccentText: ShapeStyle {
    func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        if GanchoTokens.Palette.accentIsBrand {
            return GanchoTokens.ColorPair.accentText.resolved(environment.colorScheme)
        }
        return ReadableInk(base: GanchoTokens.Palette.accent).resolve(in: environment)
    }
}

/// The accent as a fill, stepped for hover or pressed (`ButtonStates`). The
/// one place the accent's states are computed.
struct AccentFill: ShapeStyle {
    var step: Double = 0

    func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        let scheme = environment.colorScheme
        let rest =
            GanchoTokens.Palette.accentIsBrand
            ? GanchoTokens.ColorPair.accent.resolved(scheme)
            : GanchoTokens.Palette.accent.resolve(in: environment)
        return Contrast.stepped(rest, by: step, lighter: scheme == .dark)
    }
}

/// Text and glyphs on `AccentFill` at the same step.
struct OnAccentInk: ShapeStyle {
    var step: Double = 0

    func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        ContrastingForeground.ink(
            on: AccentFill(step: step).resolve(in: environment), scheme: environment.colorScheme)
    }
}

/// Any hue as text: darkened (light) or lightened (dark) until it reaches
/// 4.5:1 on the surfaces text sits on, keeping its hue.
public struct ReadableInk: ShapeStyle {
    let base: Color
    let wash: Double

    /// `wash` is the opacity of `base` filled behind the text (a tinted pill).
    public init(base: Color, onWash wash: Double = 0) {
        self.base = base
        self.wash = wash
    }

    public func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        let dark = environment.colorScheme == .dark
        // The darkest light surface and lightest dark surface text sits on.
        let surface = Color.Resolved(
            colorSpace: .sRGB, red: dark ? 0x2C / 255 : 0xE6 / 255,
            green: dark ? 0x2C / 255 : 0xE6 / 255, blue: dark ? 0x2E / 255 : 0xE8 / 255)
        let ink = base.resolve(in: environment)
        guard wash > 0 else { return Contrast.adjusted(ink, against: surface) }
        var fill = ink
        fill.opacity = ink.opacity * Float(wash)
        return Contrast.adjusted(ink, against: Contrast.composited(fill, over: surface))
    }
}

extension View {
    /// Text on a capsule of its own hue; the ink is adjusted against the wash
    /// it is drawn on, so the two can never disagree.
    public func ganchoTintedPill(_ tint: Color, wash: Double) -> some View {
        foregroundStyle(ReadableInk(base: tint, onWash: wash))
            .background(tint.opacity(wash), in: Capsule())
    }
}

extension GanchoTokens {
    /// Text and glyphs on the lime, in both appearances.
    static let onAccentInk = Color.Resolved(
        colorSpace: .sRGB, red: 0x16 / 255, green: 0x1C / 255, blue: 0)

    /// Light/dark byte triples with an opacity. `ShapeStyle`s resolve from
    /// these by colour scheme: an AppKit dynamic colour may only resolve on
    /// the main thread.
    struct ColorPair {
        let light: (Int, Int, Int)
        let dark: (Int, Int, Int)
        var lightAlpha: Double = 1
        var darkAlpha: Double = 1

        private static let graphite = (0x12, 0x14, 0x13)
        private static let white = (0xFF, 0xFF, 0xFF)

        static let brand = ColorPair(light: (0x34, 0xC7, 0x59), dark: (0x30, 0xD1, 0x58))

        static let accent = ColorPair(light: (0xC3, 0xF2, 0x2E), dark: (0xC8, 0xF5, 0x3C))
        static let accentText = ColorPair(light: (0x47, 0x75, 0x0A), dark: (0xC8, 0xF5, 0x3C))

        static let panel = ColorPair(light: (0xF6, 0xF7, 0xF6), dark: (0x17, 0x17, 0x16))
        static let card = ColorPair(light: white, dark: white, darkAlpha: 0.045)
        static let controlFill = ColorPair(
            light: graphite, dark: white, lightAlpha: 0.055, darkAlpha: 0.075)
        static let selection = ColorPair(
            light: graphite, dark: white, lightAlpha: 0.07, darkAlpha: 0.09)
        static let hairline = ColorPair(
            light: graphite, dark: white, lightAlpha: 0.10, darkAlpha: 0.085)
        static let ink = ColorPair(light: graphite, dark: (0xF5, 0xF4, 0xEF))
        static let ink2 = ColorPair(light: (0x4F, 0x53, 0x51), dark: (0xB6, 0xB5, 0xAD))
        static let ink3 = ColorPair(light: (0x62, 0x66, 0x64), dark: (0x9A, 0x99, 0x92))
        static let controlTint = ColorPair(light: graphite, dark: (0x94, 0x93, 0x8C))

        static let danger = ColorPair(
            light: StatusBytes.dangerLight, dark: StatusBytes.dangerDark)
        static let warning = ColorPair(light: StatusBytes.warning, dark: StatusBytes.warning)
        static let indigo = ColorPair(light: StatusBytes.indigo, dark: StatusBytes.indigo)
        static let agent = ColorPair(light: StatusBytes.agentLight, dark: StatusBytes.agentDark)

        #if canImport(AppKit)
            /// Appearance-dynamic, with the design's exact sRGB values.
            var nsColor: NSColor {
                NSColor(name: nil) { appearance in
                    let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                    let c = dark ? self.dark : light
                    return NSColor(
                        srgbRed: CGFloat(c.0) / 255, green: CGFloat(c.1) / 255,
                        blue: CGFloat(c.2) / 255, alpha: dark ? darkAlpha : lightAlpha)
                }
            }
        #endif

        var color: Color {
            #if canImport(AppKit)
                return Color(nsColor: nsColor)
            #elseif canImport(UIKit)
                return Color(
                    uiColor: UIColor { traits in
                        let dark = traits.userInterfaceStyle == .dark
                        let c = dark ? self.dark : light
                        return UIColor(
                            red: CGFloat(c.0) / 255, green: CGFloat(c.1) / 255,
                            blue: CGFloat(c.2) / 255, alpha: dark ? darkAlpha : lightAlpha)
                    })
            #else
                return Color(resolved(.light))
            #endif
        }

        func resolved(_ scheme: ColorScheme) -> Color.Resolved {
            let c = scheme == .dark ? dark : light
            return Color.Resolved(
                colorSpace: .sRGB, red: Float(c.0) / 255, green: Float(c.1) / 255,
                blue: Float(c.2) / 255, opacity: Float(scheme == .dark ? darkAlpha : lightAlpha))
        }
    }
}

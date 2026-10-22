import SwiftUI

#if canImport(AppKit)
    import AppKit
#elseif canImport(UIKit)
    import UIKit
#endif

/// Semantic color tokens. gancho leans on the OS materials and spends color
/// sparingly: ONE accent that follows the user's system Theme color, a fixed
/// success green, and warning/danger status hues. Green is a fill, never a
/// text colour: text on it uses `brandInk`, green text uses `accentInk`
/// (docs/design-v4/specs/V4_System_Components.md).
extension GanchoTokens {
    public enum Palette {
        // MARK: Brand green (Apple system green)

        /// gancho's brand green — the design's `--green-500`. It is BOTH the
        /// fixed success tint and the accent fallback (see `accent`).
        public static let brandGreen = dynamic(
            light: ColorPair.brand.light, dark: ColorPair.brand.dark)

        /// Deeper green for the region-selection cursor, not a global brand override.
        /// A cursor crosses other apps' light and dark content independently of our appearance.
        public static let regionSelectionCursor = Color(
            .sRGB, red: 0x2E / 255, green: 0xAD / 255, blue: 0x50 / 255, opacity: 1)

        // MARK: Semantic status roles

        /// Fixed success / "Synced" tint — ALWAYS green, regardless of the
        /// system accent. It signals a state, not a theme preference, so it
        /// must not follow `accent`.
        public static var success: Color { brandGreen }

        /// Warning status (sync paused, permission missing) — `--warning`.
        public static let warning = dynamic(
            light: (0xFF, 0x9F, 0x0A), dark: (0xFF, 0x9F, 0x0A))

        /// Danger status (sync failed, destructive). Darker than system red in
        /// light and lighter in dark, so it reads as text on every surface.
        public static let danger = dynamic(
            light: (0xD7, 0x00, 0x15), dark: (0xFF, 0x69, 0x61))

        // MARK: Ink and text derived from the brand green

        /// Text and glyphs on a brand-green fill (6.8:1 light, 8.5:1 dark).
        public static let brandInk = dynamic(light: ColorPair.ink.light, dark: ColorPair.ink.dark)

        /// Brand green as text on light surfaces; the brand itself in dark.
        public static let brandText = dynamic(
            light: ColorPair.text.light, dark: ColorPair.text.dark)

        /// Quiet fill behind green text (chips, tertiary hover).
        public static let brandTint = dynamic(
            light: ColorPair.tint.light, dark: ColorPair.tint.dark)

        /// The accent as text: the brand text green, or the system accent
        /// darkened (light) / lightened (dark) until it reaches 4.5:1.
        public static var accentInk: AccentInk { AccentInk() }

        /// The quiet fill that pairs with `accentInk`.
        public static var accentTint: AccentTint { AccentTint() }

        // MARK: Accent — follows the OS Theme color, brand green by default

        // Keep the accent source nested under Palette because callers treat it
        // as part of the design-token namespace.
        // swiftlint:disable nesting
        /// Where the accent comes from. Pure and testable: macOS writes
        /// `AppleAccentColor` to the global domain only when the user picks a
        /// specific accent in System Settings; under "Multicolor" (the default)
        /// the key is absent — and gancho uses its brand green rather than the
        /// system's default blue.
        public enum AccentSource: Sendable, Equatable { case system, brand }
        // swiftlint:enable nesting

        /// - Parameter present: whether `AppleAccentColor` exists in the global
        ///   defaults domain (i.e. the user chose a specific accent).
        public static func accentSource(appleAccentColorKeyPresent present: Bool) -> AccentSource {
            present ? .system : .brand
        }

        /// The resolved app accent. Active tab pills, "on" toggles and primary
        /// CTAs inherit it via `.ganchoTinted()` at each SwiftUI root. Success
        /// stays green via `success` — never this. Resolved at view-build time
        /// (the design sets the accent "at launch"); a system-accent change is
        /// picked up on the next launch.
        public static var accent: Color {
            #if canImport(AppKit)
                let present = UserDefaults.standard.object(forKey: "AppleAccentColor") != nil
                switch accentSource(appleAccentColorKeyPresent: present) {
                case .system: return Color(nsColor: .controlAccentColor)
                case .brand: return brandGreen
                }
            #else
                // iOS / iPadOS expose no per-app system accent — green is the default.
                return brandGreen
            #endif
        }

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

        /// The selected row's accent wash: 14 % light, 16 % dark.
        public static func selectionWashOpacity(_ scheme: ColorScheme) -> Double {
            scheme == .dark ? 0.16 : 0.14
        }

        static var accentIsBrand: Bool {
            #if canImport(AppKit)
                accentSource(
                    appleAccentColorKeyPresent: UserDefaults.standard.object(
                        forKey: "AppleAccentColor") != nil) == .brand
            #else
                true
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

        /// A light/dark-adaptive `Color` from sRGB byte triples, so the tokens
        /// match the design's exact hex values on both appearances.
        private static func dynamic(
            light: (Int, Int, Int), dark: (Int, Int, Int)
        ) -> Color {
            #if canImport(AppKit)
                return Color(
                    nsColor: NSColor(name: nil) { appearance in
                        let c =
                            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                            ? dark : light
                        return NSColor(
                            srgbRed: CGFloat(c.0) / 255, green: CGFloat(c.1) / 255,
                            blue: CGFloat(c.2) / 255, alpha: 1)
                    })
            #elseif canImport(UIKit)
                return Color(
                    uiColor: UIColor { traits in
                        let c = traits.userInterfaceStyle == .dark ? dark : light
                        return UIColor(
                            red: CGFloat(c.0) / 255, green: CGFloat(c.1) / 255,
                            blue: CGFloat(c.2) / 255, alpha: 1)
                    })
            #else
                return Color(
                    red: Double(light.0) / 255, green: Double(light.1) / 255,
                    blue: Double(light.2) / 255)
            #endif
        }
    }
}

extension GanchoTokens {
    /// Token colors for `GanchoSyntax`. The dark values are the design editor's
    /// palette (`docs/design/ui_kits/macos/snippet-editor.html`); the light
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
            return syntaxDynamicColor(light: t.light, dark: t.dark)
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
                return syntaxDynamicNSColor(light: t.light, dark: t.dark)
            }

            /// The editor's elevated code surface — near-black on dark (the
            /// design's `#15191e`), a soft off-white on light.
            public static var editorSurface: NSColor {
                syntaxDynamicNSColor(light: (0xF6, 0xF7, 0xF9), dark: (0x15, 0x19, 0x1E))
            }

            /// The line-number gutter background — a shade deeper than the code
            /// surface on each appearance.
            public static var editorGutter: NSColor {
                syntaxDynamicNSColor(light: (0xEC, 0xEE, 0xF1), dark: (0x10, 0x14, 0x18))
            }

            /// The gutter's line-number text — muted on both appearances.
            public static var editorGutterText: NSColor {
                syntaxDynamicNSColor(light: (0xA0, 0xA4, 0xAA), dark: (0x4B, 0x55, 0x60))
            }
        #endif
    }
}

extension View {
    /// Apply gancho's resolved accent (`GanchoTokens.Palette.accent`) so active
    /// controls follow the OS Theme color — or the brand green under macOS
    /// "Multicolor". Applied at every SwiftUI root (windows, panel, settings).
    public func ganchoTinted() -> some View {
        tint(GanchoTokens.Palette.accent)
            .modifier(AppLocaleModifier())
    }
}

// MARK: - Dynamic color builders shared by the syntax tokens

/// A light/dark-adaptive `Color` from sRGB byte triples. Mirrors
/// `GanchoTokens.Palette.dynamic` (which is private to `Palette`).
private func syntaxDynamicColor(light: (Int, Int, Int), dark: (Int, Int, Int)) -> Color {
    #if canImport(AppKit)
        return Color(nsColor: syntaxDynamicNSColor(light: light, dark: dark))
    #elseif canImport(UIKit)
        return Color(
            uiColor: UIColor { traits in
                let c = traits.userInterfaceStyle == .dark ? dark : light
                return UIColor(
                    red: CGFloat(c.0) / 255, green: CGFloat(c.1) / 255,
                    blue: CGFloat(c.2) / 255, alpha: 1)
            })
    #else
        return Color(
            red: Double(light.0) / 255, green: Double(light.1) / 255,
            blue: Double(light.2) / 255)
    #endif
}

#if canImport(AppKit)
    private func syntaxDynamicNSColor(
        light: (Int, Int, Int), dark: (Int, Int, Int)
    ) -> NSColor {
        NSColor(name: nil) { appearance in
            let c = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(
                srgbRed: CGFloat(c.0) / 255, green: CGFloat(c.1) / 255,
                blue: CGFloat(c.2) / 255, alpha: 1)
        }
    }
#endif

/// The accent used as text or a small glyph, legible in the appearance it
/// renders in. See `GanchoTokens.Palette.accentInk`.
public struct AccentInk: ShapeStyle {
    public func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        if GanchoTokens.Palette.accentIsBrand {
            return GanchoTokens.ColorPair.text.resolved(environment.colorScheme)
        }
        let dark = environment.colorScheme == .dark
        // The darkest light surface and lightest dark surface text sits on.
        let surface =
            dark
            ? Color(.sRGB, red: 0x2C / 255, green: 0x2C / 255, blue: 0x2E / 255)
            : Color(.sRGB, red: 0xF2 / 255, green: 0xF2 / 255, blue: 0xF3 / 255)
        return Contrast.adjusted(
            GanchoTokens.Palette.accent.resolve(in: environment),
            against: surface.resolve(in: environment))
    }
}

/// The quiet fill behind `AccentInk` text.
public struct AccentTint: ShapeStyle {
    public func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        if GanchoTokens.Palette.accentIsBrand {
            return GanchoTokens.ColorPair.tint.resolved(environment.colorScheme)
        }
        var tint = GanchoTokens.Palette.accent.resolve(in: environment)
        tint.opacity = environment.colorScheme == .dark ? 0.22 : 0.14
        return tint
    }
}

extension GanchoTokens {
    /// Light/dark byte triples. `ShapeStyle`s resolve from these by colour
    /// scheme: an AppKit dynamic colour may only resolve on the main thread.
    struct ColorPair {
        let light: (Int, Int, Int)
        let dark: (Int, Int, Int)

        static let brand = ColorPair(light: (0x34, 0xC7, 0x59), dark: (0x30, 0xD1, 0x58))
        static let ink = ColorPair(light: (0x0B, 0x2A, 0x14), dark: (0x04, 0x21, 0x0D))
        static let text = ColorPair(light: (0x1F, 0x7A, 0x3A), dark: (0x30, 0xD1, 0x58))
        static let tint = ColorPair(light: (0xE3, 0xF5, 0xE8), dark: (0x20, 0x3D, 0x28))

        func resolved(_ scheme: ColorScheme) -> Color.Resolved {
            let c = scheme == .dark ? dark : light
            return Color.Resolved(
                colorSpace: .sRGB, red: Float(c.0) / 255, green: Float(c.1) / 255,
                blue: Float(c.2) / 255)
        }
    }
}

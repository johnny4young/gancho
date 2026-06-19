import SwiftUI

#if canImport(AppKit)
    import AppKit
#elseif canImport(UIKit)
    import UIKit
#endif

/// Semantic color tokens. gancho leans on the OS materials and spends color
/// sparingly: ONE accent that follows the user's system Theme color, a fixed
/// success green, and warning/danger status hues. Source of truth for the
/// exact values is the pulled design system (`docs/design/tokens/colors.css`):
/// brand green `#34C759` (light) / `#30D158` (dark), warning `#FF9F0A`,
/// danger `#FF3B30`.
extension GanchoTokens {
    public enum Palette {
        // MARK: Brand green (Apple system green)

        /// gancho's brand green — the design's `--green-500`. It is BOTH the
        /// fixed success tint and the accent fallback (see `accent`).
        public static let brandGreen = dynamic(
            light: (0x34, 0xC7, 0x59), dark: (0x30, 0xD1, 0x58))

        // MARK: Semantic status roles

        /// Fixed success / "Synced" tint — ALWAYS green, regardless of the
        /// system accent. It signals a state, not a theme preference, so it
        /// must not follow `accent`.
        public static var success: Color { brandGreen }

        /// Warning status (sync paused, permission missing) — `--warning`.
        public static let warning = dynamic(
            light: (0xFF, 0x9F, 0x0A), dark: (0xFF, 0x9F, 0x0A))

        /// Danger status (sync failed, destructive) — `--danger`.
        public static let danger = dynamic(
            light: (0xFF, 0x3B, 0x30), dark: (0xFF, 0x3B, 0x30))

        // MARK: Accent — follows the OS Theme color, brand green by default

        /// Where the accent comes from. Pure and testable: macOS writes
        /// `AppleAccentColor` to the global domain only when the user picks a
        /// specific accent in System Settings; under "Multicolor" (the default)
        /// the key is absent — and gancho uses its brand green rather than the
        /// system's default blue.
        public enum AccentSource: Sendable, Equatable { case system, brand }

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

        // MARK: Dynamic color helper

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

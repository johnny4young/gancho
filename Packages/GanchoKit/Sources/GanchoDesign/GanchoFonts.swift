import CoreText
import SwiftUI

#if canImport(UIKit)
    import UIKit
#endif
#if canImport(AppKit)
    import AppKit
#endif

/// The bundled typefaces. Registered per process from the package's resource
/// bundle, so no target needs an Info.plist font entry.
public enum GanchoFonts {
    public enum Family: Sendable, CaseIterable {
        /// Instrument Serif: titles. Regular only.
        case serif
        /// Geist: interface text.
        case sans
        /// Geist Mono: data, keys, captions and timers.
        case mono

        var fileName: String {
            switch self {
            case .serif: "InstrumentSerif-Regular"
            case .sans: "Geist-Variable"
            case .mono: "GeistMono-Variable"
            }
        }

        /// PostScript prefix of the family's named instances.
        var postScriptPrefix: String {
            switch self {
            case .serif: "InstrumentSerif"
            case .sans: "Geist"
            case .mono: "GeistMono"
            }
        }
    }

    /// Built once, on first use from any thread.
    private static let availability = Dictionary(
        uniqueKeysWithValues: Family.allCases.map { ($0, register($0)) })

    /// Registers the faces once per process. Roles also register on first use;
    /// calling this at launch keeps that cost out of the first frame.
    public static func registerIfNeeded() {
        _ = availability
    }

    /// Whether the family resolves; false sends its role to the system fallback.
    public static func isAvailable(_ family: Family) -> Bool {
        availability[family] ?? false
    }

    private static func register(_ family: Family) -> Bool {
        if let url = Bundle.module.url(forResource: family.fileName, withExtension: "ttf") {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
        // A copy installed by the user resolves too, so ask for the face itself.
        let name = "\(family.postScriptPrefix)-Regular"
        let font = CTFontCreateWithName(name as CFString, 12, nil)
        return CTFontCopyPostScriptName(font) as String == name
    }
}

/// Type roles: serif titles, sans interface text, mono data.
public enum GanchoType {
    public enum Role: Sendable {
        case title, ui, data

        /// Rounded has no bundled face and stays on the system font.
        init?(design: Font.Design) {
            switch design {
            case .serif: self = .title
            case .monospaced: self = .data
            case .rounded: return nil
            default: self = .ui
            }
        }

        var family: GanchoFonts.Family {
            switch self {
            case .title: .serif
            case .ui: .sans
            case .data: .mono
            }
        }

        var design: Font.Design {
            switch self {
            case .title: .serif
            case .ui: .default
            case .data: .monospaced
            }
        }
    }

    /// The role's face at `size`. With `relativeTo` the size follows Dynamic
    /// Type; without it the size is fixed (the Mac scales its own text).
    public static func font(
        _ role: Role, size: CGFloat, weight: Font.Weight = .regular,
        relativeTo style: Font.TextStyle? = nil
    ) -> Font {
        font(design: role.design, size: size, weight: weight, relativeTo: style)
    }

    #if canImport(UIKit)
        /// The role's face for a bar the system draws, scaled with Dynamic
        /// Type; nil when the face did not register.
        public static func uiFont(
            _ role: Role, size: CGFloat, textStyle: UIFont.TextStyle
        ) -> UIFont? {
            guard let name = postScriptName(role, weight: .regular),
                let font = UIFont(name: name, size: size)
            else { return nil }
            return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: font)
        }
    #endif

    /// The bundled face behind a system design, or the system font when the
    /// design has no role or its face did not register.
    static func font(
        design: Font.Design, size: CGFloat, weight: Font.Weight,
        relativeTo style: Font.TextStyle? = nil
    ) -> Font {
        let role = Role(design: design)
        guard let role, let name = postScriptName(role, weight: weight) else {
            if let style { return Font.system(style, design: design, weight: weight) }
            return Font.system(size: size, weight: weight, design: design)
        }
        if let style { return Font.custom(name, size: size, relativeTo: style) }
        return Font.custom(name, fixedSize: size)
    }

    /// The named instance for a weight, or nil when the family is missing.
    /// Instances are addressed by name: `.weight(.light)` on the family would
    /// pick ExtraLight, and the serif has no weight to synthesize.
    static func postScriptName(_ role: Role, weight: Font.Weight) -> String? {
        let family = role.family
        guard GanchoFonts.isAvailable(family) else { return nil }
        guard family != .serif else { return "\(family.postScriptPrefix)-Regular" }
        return "\(family.postScriptPrefix)-\(instance(for: weight))"
    }

    static func instance(for weight: Font.Weight) -> String {
        switch weight {
        case .ultraLight, .thin, .light: "Light"
        case .medium: "Medium"
        case .semibold: "SemiBold"
        case .bold, .heavy, .black: "Bold"
        default: "Regular"
        }
    }

    #if canImport(AppKit)
        /// The role's face for AppKit text such as menu items; nil when the
        /// family did not register.
        public static func nsFont(
            _ role: Role, size: CGFloat, weight: Font.Weight = .regular
        )
            -> NSFont?
        {
            postScriptName(role, weight: weight).flatMap { NSFont(name: $0, size: size) }
        }
    #endif
}

extension View {
    /// A mono caps caption: section headers and the label over a value.
    public func ganchoCaps(size: CGFloat = 10) -> some View {
        font(GanchoType.font(.data, size: size, weight: .medium))
            .textCase(.uppercase)
            .tracking(0.6)
            .foregroundStyle(GanchoTokens.Palette.ink3)
    }
}

import CoreText
import SwiftUI

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

    private static let serifAvailable = register(.serif)
    private static let sansAvailable = register(.sans)
    private static let monoAvailable = register(.mono)

    /// Registers the families once per process. Roles also register lazily on
    /// first use; calling this at launch keeps that cost out of the first frame.
    public static func registerIfNeeded(_ families: Set<Family> = Set(Family.allCases)) {
        for family in families { _ = isAvailable(family) }
    }

    /// Whether the family resolves; false sends its role to the system fallback.
    public static func isAvailable(_ family: Family) -> Bool {
        switch family {
        case .serif: serifAvailable
        case .sans: sansAvailable
        case .mono: monoAvailable
        }
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

        var family: GanchoFonts.Family {
            switch self {
            case .title: .serif
            case .ui: .sans
            case .data: .mono
            }
        }

        var fallback: Font.Design {
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
        guard let name = postScriptName(role, weight: weight) else {
            if let style {
                return Font.system(style, design: role.fallback, weight: weight)
            }
            return Font.system(size: size, weight: weight, design: role.fallback)
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
}

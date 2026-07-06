import SwiftUI

/// The user's manual app-language override. `.system` follows the OS; the others
/// force a bundle localization. Applied live to every gancho window through
/// `ganchoTinted()` (which carries `AppLocaleModifier`), and stored in the
/// standard defaults so both platforms and every window read the same choice.
public enum AppLanguage: String, CaseIterable, Identifiable, Sendable {
    case system, english, spanish

    public var id: String { rawValue }

    /// UserDefaults key for the persisted choice.
    public static let storageKey = "app-language"

    /// Shown in the picker — each language in its OWN name (the convention for a
    /// language selector), so it reads the same whatever the current UI language.
    public var displayName: String {
        switch self {
        case .system: "System"
        case .english: "English"
        case .spanish: "Español"
        }
    }

    /// nil = follow the system; otherwise a forced bundle localization.
    public var localeIdentifier: String? {
        switch self {
        case .system: nil
        case .english: "en"
        case .spanish: "es"
        }
    }

    public var resolvedLocale: Locale {
        localeIdentifier.map(Locale.init(identifier:)) ?? Locale.autoupdatingCurrent
    }

    /// The current choice from standard defaults (`.system` when unset).
    public static var current: AppLanguage {
        AppLanguage(rawValue: UserDefaults.standard.string(forKey: storageKey) ?? "") ?? .system
    }
}

/// Applies the manual app-language override to a view tree as `\.locale`,
/// re-rendering live when the choice changes (it observes the stored value).
public struct AppLocaleModifier: ViewModifier {
    @AppStorage(AppLanguage.storageKey) private var raw = AppLanguage.system.rawValue

    public init() {}

    public func body(content: Content) -> some View {
        content.environment(\.locale, (AppLanguage(rawValue: raw) ?? .system).resolvedLocale)
    }
}

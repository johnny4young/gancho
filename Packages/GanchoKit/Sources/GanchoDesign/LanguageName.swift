import Foundation

/// The one place a language code becomes a name the user reads, in the
/// user's own language ("Spanish", "Español"). Every language menu and
/// translation header goes through here so they can never spell it two ways.
public enum LanguageName {
    /// "es" → "Spanish" under an English UI; the code itself when the system
    /// has no name for it.
    public static func localized(code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code) ?? code
    }

    /// The language's base code is what gets named, so "es-MX" reads
    /// "Spanish", not "Spanish (Mexico)"; the minimal identifier is the
    /// fallback for a language with no separable code.
    public static func localized(_ language: Locale.Language) -> String {
        localized(code: language.languageCode?.identifier ?? language.minimalIdentifier)
    }
}

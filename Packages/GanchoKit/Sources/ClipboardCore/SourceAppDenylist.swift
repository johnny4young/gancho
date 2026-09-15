import Foundation

/// Apps whose copies are never captured, decided BEFORE any content read
/// (the veto only needs the frontmost bundle ID — metadata).
///
/// Two layers: a built-in suggestion list (password managers and banking
/// apps that users expect to be excluded even before configuring anything)
/// and the user's own additions. Both persist as one JSON blob.
public struct SourceAppDenylist: Sendable, Equatable, Codable {
    /// The two families of built-in exclusions. Settings groups the list by
    /// category so twenty rows read as two short ones.
    public enum SuggestionCategory: String, CaseIterable, Sendable, Codable {
        case passwordManagers
        case banking
    }

    /// One built-in exclusion: the bundle id the veto matches, a readable
    /// name for when the app is not installed (no icon or display name to
    /// resolve), and its category.
    public struct Suggestion: Sendable, Hashable, Identifiable {
        public let id: String
        public let name: String
        public let category: SuggestionCategory

        public init(id: String, name: String, category: SuggestionCategory) {
            self.id = id
            self.name = name
            self.category = category
        }
    }

    /// Password managers + banking apps preloaded as suggestions. These
    /// apps already mark sensitive copies with `org.nspasteboard` types —
    /// the denylist is defense in depth for the ones that sometimes don't
    /// (web wrappers, older builds). Ordered as Settings lists them.
    public static let suggestions: [Suggestion] = [
        Suggestion(id: "com.1password.1password", name: "1Password", category: .passwordManagers),
        Suggestion(
            id: "com.agilebits.onepassword7", name: "1Password 7", category: .passwordManagers),
        Suggestion(id: "com.bitwarden.desktop", name: "Bitwarden", category: .passwordManagers),
        Suggestion(id: "com.apple.Passwords", name: "Passwords", category: .passwordManagers),
        Suggestion(
            id: "com.apple.keychainaccess", name: "Keychain Access", category: .passwordManagers),
        Suggestion(id: "com.lastpass.LastPass", name: "LastPass", category: .passwordManagers),
        Suggestion(
            id: "com.dashlane.dashlanephonefinal", name: "Dashlane", category: .passwordManagers),
        Suggestion(id: "org.keepassxc.keepassxc", name: "KeePassXC", category: .passwordManagers),
        Suggestion(id: "com.proton.pass", name: "Proton Pass", category: .passwordManagers),
        Suggestion(id: "com.enpass.Enpass-Desktop", name: "Enpass", category: .passwordManagers),
        // Strongbox's Mac App Store build.
        Suggestion(
            id: "com.markmcguill.strongbox.mac", name: "Strongbox", category: .passwordManagers),
        // KeePassium ships on macOS via universal purchase (Catalyst), which
        // keeps the iOS bundle id.
        Suggestion(id: "com.keepassium.ios", name: "KeePassium", category: .passwordManagers),
        // MacPass (open source; id from the project's Info.plist).
        Suggestion(
            id: "com.hicknhacksoftware.MacPass", name: "MacPass", category: .passwordManagers),
        // NordPass's macOS desktop app.
        Suggestion(id: "com.nordpass.macos", name: "NordPass", category: .passwordManagers),
        // Banking (the common Mac wrappers)
        Suggestion(id: "com.apple.PassbookUIService", name: "Wallet", category: .banking),
        Suggestion(id: "com.paypal.PPClient", name: "PayPal", category: .banking),
        Suggestion(id: "com.wise.WiseMacOS", name: "Wise", category: .banking),
        Suggestion(id: "com.revolut.osx", name: "Revolut", category: .banking),
        // iPhone banking apps run unchanged on Apple-silicon Macs and keep
        // their iOS bundle ids.
        Suggestion(id: "com.venmo.TouchFree", name: "Venmo", category: .banking),
        Suggestion(id: "com.squareup.cash", name: "Cash App", category: .banking)
    ]

    /// The suggested bundle ids as the veto checks them.
    public static let suggestedBundleIDs: Set<String> = Set(suggestions.map(\.id))

    /// Whether `raw` has the shape of a bundle identifier: at least two
    /// dot-separated parts made of letters, digits and hyphens. A lenient
    /// syntax check for the manual-entry field, not a registry lookup — it
    /// exists so "safari" is refused live instead of silently never matching.
    public static func isPlausibleBundleIdentifier(_ raw: String) -> Bool {
        guard let trimmed = normalizedBundleID(raw) else { return false }
        let parts = trimmed.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty
                && part.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }
    }

    /// Bundle IDs the user added on top of the suggestions.
    public var userBundleIDs: Set<String>
    /// Suggested entries the user explicitly re-enabled (captures allowed).
    public var disabledSuggestions: Set<String>

    public init(userBundleIDs: Set<String> = [], disabledSuggestions: Set<String> = []) {
        self.userBundleIDs = Set(userBundleIDs.compactMap(Self.normalizedBundleID))
        self.disabledSuggestions = Set(disabledSuggestions.compactMap(Self.normalizedBundleID))
    }

    /// The veto check the monitor runs pre-read.
    public func contains(_ bundleID: String?) -> Bool {
        guard let bundleID = bundleID.flatMap(Self.normalizedBundleID) else { return false }
        if userBundleIDs.contains(bundleID) { return true }
        return Self.suggestedBundleIDs.contains(bundleID)
            && !disabledSuggestions.contains(bundleID)
    }

    public mutating func add(_ bundleID: String) {
        guard let bundleID = Self.normalizedBundleID(bundleID) else { return }
        userBundleIDs.insert(bundleID)
        disabledSuggestions.remove(bundleID)
    }

    public mutating func remove(_ bundleID: String) {
        guard let bundleID = Self.normalizedBundleID(bundleID) else { return }
        userBundleIDs.remove(bundleID)
        if Self.suggestedBundleIDs.contains(bundleID) {
            disabledSuggestions.insert(bundleID)
        }
    }

    /// Re-excludes every suggested entry the user had allowed again — the
    /// Settings "Restore default exclusions" affordance. User-added entries
    /// are untouched.
    public mutating func restoreSuggestions() {
        disabledSuggestions = []
    }

    private static let defaultsKey = "source-app-denylist"

    public static func load(from defaults: UserDefaults) -> SourceAppDenylist {
        guard let data = defaults.data(forKey: defaultsKey),
            let list = try? JSONDecoder().decode(SourceAppDenylist.self, from: data)
        else { return SourceAppDenylist() }
        return list
    }

    public func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }

    private static func normalizedBundleID(_ bundleID: String) -> String? {
        let trimmed = bundleID.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

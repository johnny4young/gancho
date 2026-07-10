import Foundation

/// Apps whose copies are never captured, decided BEFORE any content read
/// (the veto only needs the frontmost bundle ID — metadata).
///
/// Two layers: a built-in suggestion list (password managers and banking
/// apps that users expect to be excluded even before configuring anything)
/// and the user's own additions. Both persist as one JSON blob.
public struct SourceAppDenylist: Sendable, Equatable, Codable {
    /// Password managers + banking apps preloaded as suggestions. These
    /// apps already mark sensitive copies with `org.nspasteboard` types —
    /// the denylist is defense in depth for the ones that sometimes don't
    /// (web wrappers, older builds).
    public static let suggestedBundleIDs: Set<String> = [
        // Password managers
        "com.1password.1password",
        "com.agilebits.onepassword7",
        "com.bitwarden.desktop",
        "com.apple.Passwords",
        "com.apple.keychainaccess",
        "com.lastpass.LastPass",
        "com.dashlane.dashlanephonefinal",
        "org.keepassxc.keepassxc",
        "com.proton.pass",
        "com.enpass.Enpass-Desktop",
        // Strongbox's Mac App Store build.
        "com.markmcguill.strongbox.mac",
        // KeePassium ships on macOS via universal purchase (Catalyst), which
        // keeps the iOS bundle id.
        "com.keepassium.ios",
        // MacPass (open source; id from the project's Info.plist).
        "com.hicknhacksoftware.MacPass",
        // NordPass's macOS desktop app.
        "com.nordpass.macos",
        // Banking (the common Mac wrappers)
        "com.apple.PassbookUIService",
        "com.paypal.PPClient",
        "com.wise.WiseMacOS",
        "com.revolut.osx",
        // iPhone banking apps run unchanged on Apple-silicon Macs and keep
        // their iOS bundle ids.
        "com.venmo.TouchFree",
        "com.squareup.cash"
    ]

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

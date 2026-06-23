import Foundation

/// On-device intelligence toggles (the design's "Intelligence" screen). Each
/// one gates a REAL enrichment stage — never a decorative switch. The
/// deterministic tier-0 classifier is always on and has no toggle here.
///
/// Persisted as one JSON blob under a single defaults key. Decoding tolerates
/// missing keys (a newly added toggle defaults on instead of resetting the
/// others), so the blob survives across versions.
public struct IntelligencePreferences: Sendable, Equatable, Codable {
    /// Tier 1 — Apple Intelligence writes a short, specific title (fallback-safe).
    public var intelligentTitles: Bool
    /// On-device sentence embeddings index history for meaning-based search.
    public var semanticSearch: Bool
    /// On-device OCR makes image clips findable by the words inside them.
    public var searchableScreenshots: Bool
    /// Detect copied secrets and mask + auto-expire them (the deterministic
    /// detector; the password-manager veto is separate and always on).
    public var detectSecrets: Bool
    /// Tier 1 — Apple Intelligence rewrites a clip on demand (summarize, fix
    /// grammar, change tone, key points) before pasting. On-device only.
    public var smartPaste: Bool
    /// Suggest the board a clip likely belongs to, from the semantic neighbors
    /// of how you've filed before. Only ever suggests — never files silently.
    public var autoBoard: Bool

    public init(
        intelligentTitles: Bool = true,
        semanticSearch: Bool = true,
        searchableScreenshots: Bool = true,
        detectSecrets: Bool = true,
        smartPaste: Bool = true,
        autoBoard: Bool = true
    ) {
        self.intelligentTitles = intelligentTitles
        self.semanticSearch = semanticSearch
        self.searchableScreenshots = searchableScreenshots
        self.detectSecrets = detectSecrets
        self.smartPaste = smartPaste
        self.autoBoard = autoBoard
    }

    /// Missing keys default ON — adding a toggle later must not silently flip
    /// the others off when an older blob is read back.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        intelligentTitles =
            try container.decodeIfPresent(Bool.self, forKey: .intelligentTitles) ?? true
        semanticSearch = try container.decodeIfPresent(Bool.self, forKey: .semanticSearch) ?? true
        searchableScreenshots =
            try container.decodeIfPresent(Bool.self, forKey: .searchableScreenshots) ?? true
        detectSecrets = try container.decodeIfPresent(Bool.self, forKey: .detectSecrets) ?? true
        smartPaste = try container.decodeIfPresent(Bool.self, forKey: .smartPaste) ?? true
        autoBoard = try container.decodeIfPresent(Bool.self, forKey: .autoBoard) ?? true
    }

    private static let defaultsKey = "intelligence-preferences"

    public static func load(from defaults: UserDefaults) -> IntelligencePreferences {
        guard let data = defaults.data(forKey: defaultsKey),
            let prefs = try? JSONDecoder().decode(IntelligencePreferences.self, from: data)
        else { return IntelligencePreferences() }
        return prefs
    }

    public func save(to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.defaultsKey)
    }
}

import Foundation
import GRDB

/// Rule-based live collections: a saved predicate over kind / source app /
/// text match / pinned, evaluated as a query (never materialized — the
/// collection is always current). The AI layer can PROPOSE rules later;
/// the engine below is deterministic.
public struct SmartCollectionRule: Sendable, Equatable, Codable, Identifiable {
    public var id: UUID
    public var name: String
    public var kinds: Set<ClipContentKind>?
    public var sourceAppBundleID: String?
    public var textContains: String?
    public var pinnedOnly: Bool
    public var boardID: UUID?
    public var searchMode: ClipSearchQuery.Mode?

    public init(
        id: UUID = UUID(), name: String, kinds: Set<ClipContentKind>? = nil,
        sourceAppBundleID: String? = nil, textContains: String? = nil, pinnedOnly: Bool = false,
        boardID: UUID? = nil, searchMode: ClipSearchQuery.Mode? = nil
    ) {
        self.id = id
        self.name = name
        self.kinds = kinds
        self.sourceAppBundleID = sourceAppBundleID
        self.textContains = textContains
        self.pinnedOnly = pinnedOnly
        self.boardID = boardID
        self.searchMode = searchMode
    }

    public var query: ClipSearchQuery {
        ClipSearchQuery(
            text: textContains ?? "", mode: searchMode ?? .fuzzy, kinds: kinds,
            sourceAppBundleID: sourceAppBundleID, boardID: boardID, pinnedOnly: pinnedOnly)
    }

    static let defaultsKey = "smart-collections"

    public static func loadAll(from defaults: UserDefaults) -> [SmartCollectionRule] {
        guard let data = defaults.data(forKey: defaultsKey),
            let rules = try? JSONDecoder().decode([SmartCollectionRule].self, from: data)
        else { return [] }
        return rules
    }

    public static func saveAll(_ rules: [SmartCollectionRule], to defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(rules) else { return }
        defaults.set(data, forKey: defaultsKey)
    }
}

extension GRDBClipboardStore {
    /// Evaluates a rule as a live query (FTS for the text part).
    public func items(
        matching rule: SmartCollectionRule, limit: Int = 100
    ) async throws
        -> [ClipItem]
    {
        guard rule.kinds?.isEmpty != true else { return [] }
        if let boardID = rule.boardID,
            !(try await pinboards()).contains(where: { $0.id == boardID })
        {
            throw SavedFilterError.missingBoard
        }
        if (rule.textContains ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            rule.searchMode != .regex, rule.kinds == nil, rule.sourceAppBundleID == nil,
            rule.boardID == nil, !rule.pinnedOnly
        {
            return try await recentForBrowse(offset: 0, limit: limit)
        }
        return try await search(rule.query, limit: limit)
    }
}

/// Replay detection: content the user keeps re-copying is snippet material.
/// Re-copies bump `lastUsedAt` on the SAME row (dedupe), so "used recently
/// AND old AND not yet a snippet" is the signal.
public struct SnippetSuggestor: Sendable {
    private let store: GRDBClipboardStore

    public init(store: GRDBClipboardStore) {
        self.store = store
    }

    /// Clips re-used after at least `minAge` since creation — the replay
    /// pattern — that aren't snippets or sensitive yet.
    public func suggestions(
        minAge: TimeInterval = 86_400, limit: Int = 5, now: Date = .now
    ) async throws -> [ClipItem] {
        try await store.writer.read { db in
            try ClipRow.fetchAll(
                db,
                sql: """
                    SELECT \(ClipRow.metadataSelectionSQL) FROM clip
                    WHERE isSnippet = 0 AND isSensitive = 0 AND isArchived = 0
                      AND lastUsedAt IS NOT NULL
                      AND (julianday(lastUsedAt) - julianday(createdAt)) * 86400 >= ?
                    ORDER BY lastUsedAt DESC LIMIT ?
                    """, arguments: [minAge, limit]
            ).map(\.item)
        }
    }
}

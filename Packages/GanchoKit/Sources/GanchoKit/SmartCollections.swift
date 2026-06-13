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

    public init(
        id: UUID = UUID(), name: String, kinds: Set<ClipContentKind>? = nil,
        sourceAppBundleID: String? = nil, textContains: String? = nil, pinnedOnly: Bool = false
    ) {
        self.id = id
        self.name = name
        self.kinds = kinds
        self.sourceAppBundleID = sourceAppBundleID
        self.textContains = textContains
        self.pinnedOnly = pinnedOnly
    }

    private static let defaultsKey = "smart-collections"

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
        if let text = rule.textContains, !text.isEmpty {
            var hits = try await search(
                ClipSearchQuery(
                    text: text, kinds: rule.kinds,
                    sourceAppBundleID: rule.sourceAppBundleID),
                limit: limit)
            if rule.pinnedOnly { hits = hits.filter(\.isPinned) }
            return hits
        }
        return try await writer.read { db in
            var query = ClipRow.filter(Column("isArchived") == false)
            if let kinds = rule.kinds, !kinds.isEmpty {
                query = query.filter(kinds.map(\.rawValue).contains(Column("kind")))
            }
            if let app = rule.sourceAppBundleID {
                query = query.filter(Column("sourceAppBundleID") == app)
            }
            if rule.pinnedOnly {
                query = query.filter(Column("isPinned") == true)
            }
            return try query.order(Column("createdAt").desc).limit(limit)
                .fetchAll(db).map(\.item)
        }
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
                    SELECT * FROM clip
                    WHERE isSnippet = 0 AND isSensitive = 0 AND isArchived = 0
                      AND lastUsedAt IS NOT NULL
                      AND (julianday(lastUsedAt) - julianday(createdAt)) * 86400 >= ?
                    ORDER BY lastUsedAt DESC LIMIT ?
                    """, arguments: [minAge, limit]
            ).map(\.item)
        }
    }
}

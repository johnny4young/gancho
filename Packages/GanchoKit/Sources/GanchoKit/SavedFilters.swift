import Foundation
import GRDB

public enum SavedFilterError: Error, Equatable {
    case missingBoard, invalidName, invalidLegacyData
}

/// Local definitions only: deliberately absent from the CloudKit feed.
public protocol SavedFilterStoring: Sendable {
    func savedFilters() async throws -> [SmartCollectionRule]
    func saveFilter(_ rule: SmartCollectionRule) async throws
    func deleteFilter(id: UUID) async throws
    func importLegacyFilters(_ rules: [SmartCollectionRule]) async throws
}

extension GRDBClipboardStore: SavedFilterStoring {
    public func savedFilters() async throws -> [SmartCollectionRule] {
        try await writer.read { db in
            try Data.fetchAll(db, sql: "SELECT definition FROM saved_filter ORDER BY rowid")
                .map { try JSONDecoder().decode(SmartCollectionRule.self, from: $0) }
        }
    }

    public func saveFilter(_ rule: SmartCollectionRule) async throws {
        guard !rule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw SavedFilterError.invalidName
        }
        let data = try JSONEncoder().encode(rule)
        try await writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO saved_filter (id, definition) VALUES (?, ?)
                    ON CONFLICT (id) DO UPDATE SET definition = excluded.definition
                    """, arguments: [rule.id.uuidString, data])
        }
    }

    public func deleteFilter(id: UUID) async throws {
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM saved_filter WHERE id = ?", arguments: [id.uuidString])
        }
    }

    /// Atomic and retry-safe. A migrated definition edited in the destination
    /// must not be overwritten if clearing legacy preferences was interrupted.
    public func importLegacyFilters(_ rules: [SmartCollectionRule]) async throws {
        let records = try rules.map { ($0.id.uuidString, try JSONEncoder().encode($0)) }
        try await writer.write { db in
            for (id, data) in records {
                try db.execute(
                    sql: "INSERT OR IGNORE INTO saved_filter (id, definition) VALUES (?, ?)",
                    arguments: [id, data])
            }
        }
    }
}

public enum SavedFilterMigration {
    /// Preferences remain intact after any decoding or database failure.
    @MainActor public static func migrate(
        from defaults: UserDefaults, to store: any SavedFilterStoring
    ) async throws {
        guard let data = defaults.data(forKey: SmartCollectionRule.defaultsKey) else { return }
        let rules: [SmartCollectionRule]
        do { rules = try JSONDecoder().decode([SmartCollectionRule].self, from: data) } catch {
            throw SavedFilterError.invalidLegacyData
        }
        try await store.importLegacyFilters(rules)
        if defaults.data(forKey: SmartCollectionRule.defaultsKey) == data {
            defaults.removeObject(forKey: SmartCollectionRule.defaultsKey)
        }
    }
}

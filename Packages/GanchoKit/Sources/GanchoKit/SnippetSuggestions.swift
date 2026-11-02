import Foundation
import GRDB

/// What the user chose for a suggested snippet. Local to this device: a
/// suggestion is a nudge, and `clip` rows sync, so the choice lives apart.
public enum SnippetSuggestionDecision: String, Sendable {
    /// Never suggest this clip again.
    case never
    /// Hide it until it earns the threshold again.
    case dismissed
}

/// The first suggestions to show and how many there are in all.
public struct SnippetSuggestions: Sendable, Equatable {
    public static let empty = SnippetSuggestions(items: [], total: 0)

    public var items: [ClipItem]
    public var total: Int

    public init(items: [ClipItem], total: Int) {
        self.items = items
        self.total = total
    }
}

extension GRDBClipboardStore {
    static func registerSnippetSuggestionMigration(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration(
            GanchoDatabaseMigrator.Identifier.snippetSuggestions.rawValue
        ) { db in
            try db.create(table: "snippet_suggestion") { table in
                table.primaryKey("clipID", .text).references("clip", onDelete: .cascade)
                table.column("state", .text).notNull()
                table.column("usesAtDecision", .integer).notNull()
                table.column("decidedAt", .datetime).notNull()
            }
        }
    }

    /// Clips that earned a suggestion: never a snippet already, a secret or a
    /// masked kind, and not one the user turned down. Binds `requiredUses` once.
    static func snippetCandidateSQL(usesComparison: String) -> String {
        """
        isSnippet = 0 AND isSensitive = 0 AND isArchived = 0
        AND kind NOT IN (\(PasteEventLog.maskedKindsSQL))
        AND uses \(usesComparison) ? + COALESCE((
            SELECT usesAtDecision FROM snippet_suggestion
            WHERE clipID = clip.id AND state = '\(SnippetSuggestionDecision.dismissed.rawValue)'
        ), 0)
        AND NOT EXISTS (
            SELECT 1 FROM snippet_suggestion
            WHERE clipID = clip.id AND state = '\(SnippetSuggestionDecision.never.rawValue)'
        )
        """
    }

    /// The most used candidates first. Metadata only; no content is loaded.
    public func snippetSuggestions(
        limit: Int = 3, requiredUses: Int = SnippetLimits.promotionSuggestionUseThreshold,
        now: Date = .now
    ) async throws -> SnippetSuggestions {
        guard limit > 0 else { return .empty }
        return try await writer.read { db in
            let candidates =
                ClipRow
                .filter(
                    sql: Self.snippetCandidateSQL(usesComparison: ">="),
                    arguments: [requiredUses]
                )
                .filter(sql: Self.unexpiredPredicate, arguments: [now])
            let items =
                try candidates
                .select(ClipRow.metadataColumns)
                .order(Column("uses").desc, Column("lastUsedAt").desc)
                .limit(limit)
                .fetchAll(db)
                .map(\.item)
            return SnippetSuggestions(items: items, total: try candidates.fetchCount(db))
        }
    }

    /// Records the choice with the clip's uses at this moment. A missing clip
    /// records nothing, and Never stays Never.
    public func decideSnippetSuggestion(
        id: UUID, _ decision: SnippetSuggestionDecision, now: Date = .now
    ) async throws {
        try await writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO snippet_suggestion (clipID, state, usesAtDecision, decidedAt)
                    SELECT id, ?, uses, ? FROM clip WHERE id = ?
                    ON CONFLICT(clipID) DO UPDATE SET
                        state = excluded.state,
                        usesAtDecision = excluded.usesAtDecision,
                        decidedAt = excluded.decidedAt
                    WHERE snippet_suggestion.state != ?
                    """,
                arguments: [
                    decision.rawValue, now, id.uuidString, SnippetSuggestionDecision.never.rawValue
                ])
        }
    }
}

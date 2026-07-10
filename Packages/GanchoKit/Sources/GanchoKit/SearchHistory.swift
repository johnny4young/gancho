import Foundation
import GRDB

extension GRDBClipboardStore {
    /// How many searches the history keeps (newest by use win). Small on
    /// purpose: this is a recall aid, not another archive.
    public static let searchHistoryCap = 50

    /// Remembers a successful search (one that led to a paste). Upserts by the
    /// query text — repeating a search bumps its counter and freshens its
    /// recency rather than duplicating the row (the schema's UNIQUE is plain
    /// ABORT, so the update stays explicit here) — then trims the table to the
    /// cap. LOCAL ONLY by design: search queries can be as sensitive as clip
    /// content, so they never sync and are erasable in one call.
    public func recordSearch(_ query: String, now: Date = .now) async throws {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try await writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO search_history (query, uses, lastUsedAt)
                    VALUES (?, 1, ?)
                    ON CONFLICT(query) DO UPDATE SET uses = uses + 1, lastUsedAt = ?
                    """,
                arguments: [trimmed, now, now])
            try db.execute(
                sql: """
                    DELETE FROM search_history WHERE id NOT IN (
                        SELECT id FROM search_history ORDER BY lastUsedAt DESC LIMIT ?
                    )
                    """,
                arguments: [Self.searchHistoryCap])
        }
    }

    /// The most recent searches, newest first — the ⌘↑ recall list.
    public func recentSearches(limit: Int = 5) async throws -> [String] {
        // SQLite treats a negative LIMIT as "no limit", which would return the
        // whole table — clamp so a bad argument can never widen the read.
        guard limit > 0 else { return [] }
        return try await writer.read { db in
            try String.fetchAll(
                db,
                sql: "SELECT query FROM search_history ORDER BY lastUsedAt DESC LIMIT ?",
                arguments: [limit])
        }
    }

    /// Forgets every remembered search — the privacy toggle's OFF action.
    public func clearSearchHistory() async throws {
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM search_history")
        }
    }
}

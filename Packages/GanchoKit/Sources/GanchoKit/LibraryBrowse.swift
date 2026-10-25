import Foundation
import GRDB

/// One Library page request: a sidebar scope, an optional kind set and a
/// direction. Rows come pinned first, then by capture time, so the date
/// groups stay contiguous in either direction.
public struct LibraryBrowseQuery: Sendable, Equatable {
    public enum Scope: Sendable, Equatable {
        case all, pinned
        case board(UUID)
    }

    public var scope: Scope
    /// nil = every kind; an empty set matches nothing.
    public var kinds: Set<ClipContentKind>?
    public var oldestFirst: Bool

    public init(scope: Scope, kinds: Set<ClipContentKind>? = nil, oldestFirst: Bool = false) {
        self.scope = scope
        self.kinds = kinds
        self.oldestFirst = oldestFirst
    }
}

/// The Library's paged reads, totals and per-page board membership, counted
/// with the same visibility as the lists (no archived or expired clips).
public protocol LibraryBrowsing: Sendable {
    func libraryItems(
        _ query: LibraryBrowseQuery, offset: Int, limit: Int
    ) async throws
        -> [ClipItem]
    func libraryCount(_ query: LibraryBrowseQuery) async throws -> Int
    /// Membership for a page of clips in one read; clips on no board are absent.
    func boardIDs(forClips clipIDs: [UUID]) async throws -> [UUID: Set<UUID>]
    /// How many clips a saved filter holds. A regex rule counts its matches
    /// within the bounded regex scan, so a huge history reads as a floor.
    func count(matching rule: SmartCollectionRule) async throws -> Int
}

extension GRDBClipboardStore: LibraryBrowsing {
    public func libraryItems(
        _ query: LibraryBrowseQuery, offset: Int, limit: Int
    ) async throws -> [ClipItem] {
        guard limit > 0, query.kinds?.isEmpty != true else { return [] }
        var (filter, arguments) = Self.libraryFilter(query)
        arguments += [limit, max(offset, 0)]
        let direction = query.oldestFirst ? "ASC" : "DESC"
        return try await writer.read { [filter, arguments] db in
            try ClipRow.fetchAll(
                db,
                sql: """
                    SELECT \(ClipRow.metadataSelectionSQL) FROM clip WHERE \(filter)
                    ORDER BY clip.isPinned DESC, clip.createdAt \(direction), clip.id \(direction)
                    LIMIT ? OFFSET ?
                    """,
                arguments: arguments
            ).map(\.item)
        }
    }

    public func libraryCount(_ query: LibraryBrowseQuery) async throws -> Int {
        guard query.kinds?.isEmpty != true else { return 0 }
        let (filter, arguments) = Self.libraryFilter(query)
        return try await writer.read { db in
            try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM clip WHERE \(filter)", arguments: arguments) ?? 0
        }
    }

    public func boardIDs(forClips clipIDs: [UUID]) async throws -> [UUID: Set<UUID>] {
        guard !clipIDs.isEmpty else { return [:] }
        // One bound JSON array, so a large page never hits SQLite's variable limit.
        let ids = "[" + clipIDs.map { "\"\($0.uuidString)\"" }.joined(separator: ",") + "]"
        return try await writer.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT clipID, boardID FROM clip_board
                    WHERE clipID IN (SELECT value FROM json_each(?))
                    """,
                arguments: [ids])
            var membership: [UUID: Set<UUID>] = [:]
            for row in rows {
                guard let clip = UUID(uuidString: row["clipID"]),
                    let board = UUID(uuidString: row["boardID"])
                else { continue }
                membership[clip, default: []].insert(board)
            }
            return membership
        }
    }

    public func count(matching rule: SmartCollectionRule) async throws -> Int {
        guard rule.kinds?.isEmpty != true else { return 0 }
        if let boardID = rule.boardID,
            !(try await pinboards()).contains(where: { $0.id == boardID })
        {
            throw SavedFilterError.missingBoard
        }
        let query = rule.query
        if query.mode == .regex {
            return try await search(query, limit: Self.regexScanCeiling).count
        }
        let match = query.ftsMatchExpression()
        let unconstrained =
            match == nil && query.kinds == nil && query.sourceAppBundleID == nil
            && query.boardID == nil && !query.pinnedOnly && query.createdBefore == nil
            && query.deviceName == nil
        if unconstrained { return try await count() }
        return try await writer.read { db in
            var sql = "SELECT COUNT(*) FROM clip"
            var arguments: [any DatabaseValueConvertible] = []
            if let match {
                sql += " JOIN clip_fts ON clip_fts.rowid = clip.rowid WHERE clip_fts MATCH ? AND"
                arguments.append(match)
            } else {
                sql += " WHERE"
            }
            sql += " clip.isArchived = 0"
            Self.appendFilters(for: query, to: &sql, arguments: &arguments)
            return try Int.fetchOne(db, sql: sql, arguments: StatementArguments(arguments)) ?? 0
        }
    }

    private static func libraryFilter(
        _ query: LibraryBrowseQuery
    ) -> (String, StatementArguments) {
        var sql = "clip.isArchived = 0 AND \(unexpiredPredicate)"
        var arguments: [any DatabaseValueConvertible] = [Date.now]
        switch query.scope {
        case .all: break
        case .pinned: sql += " AND clip.isPinned = 1"
        case .board(let id):
            sql += " AND clip.id IN (SELECT clipID FROM clip_board WHERE boardID = ?)"
            arguments.append(id.uuidString)
        }
        if let kinds = query.kinds {
            let placeholders = Array(repeating: "?", count: kinds.count).joined(separator: ",")
            sql += " AND clip.kind IN (\(placeholders))"
            arguments.append(contentsOf: kinds.map(\.rawValue).sorted())
        }
        return (sql, StatementArguments(arguments))
    }
}

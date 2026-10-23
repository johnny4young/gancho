import Foundation
import GRDB

/// Visible clips overall and per board, read from one snapshot.
public struct ScopeCountSnapshot: Sendable, Equatable {
    public var total: Int
    /// Keyed by board id; a board with no visible member is absent.
    public var boards: [UUID: Int]
}

/// Clip totals for the panel's scope chips, counted with the same visibility
/// rules as the panel's own list (no archived or expired clips).
public protocol ScopeCountProviding: Sendable {
    /// Leaves out `excluded`, rows the caller already hides (pending deletes).
    func scopeCounts(excluding excluded: Set<UUID>) async throws -> ScopeCountSnapshot
}

extension GRDBClipboardStore: ScopeCountProviding {
    public func scopeCounts(excluding excluded: Set<UUID>) async throws -> ScopeCountSnapshot {
        let skipped = excluded.map(\.uuidString)
        var visible = "clip.isArchived = 0 AND \(Self.unexpiredPredicate)"
        if !skipped.isEmpty {
            let placeholders = Array(repeating: "?", count: skipped.count).joined(separator: ",")
            visible += " AND clip.id NOT IN (\(placeholders))"
        }
        let now = Date.now
        return try await writer.read { [visible] db in
            var arguments: StatementArguments = [now]
            arguments += StatementArguments(skipped)
            let total =
                try Int.fetchOne(
                    db, sql: "SELECT COUNT(*) FROM clip WHERE \(visible)", arguments: arguments)
                ?? 0
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT clip_board.boardID AS boardID, COUNT(*) AS total
                    FROM clip_board JOIN clip ON clip.id = clip_board.clipID
                    WHERE \(visible)
                    GROUP BY clip_board.boardID
                    """,
                arguments: arguments)
            var boards: [UUID: Int] = [:]
            for row in rows {
                guard let id = UUID(uuidString: row["boardID"]) else { continue }
                boards[id] = row["total"]
            }
            return ScopeCountSnapshot(total: total, boards: boards)
        }
    }
}

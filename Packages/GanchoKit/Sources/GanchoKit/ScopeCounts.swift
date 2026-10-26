import Foundation
import GRDB

/// Visible clips overall and per board, read from one snapshot.
public struct ScopeCountSnapshot: Sendable, Equatable {
    public var total: Int
    /// Keyed by board id; a board with no visible member is absent.
    public var boards: [UUID: Int]
    /// Keyed by kind, read like a row's kind (unknown values count as text);
    /// a kind with no visible clip is absent. Sums to `total`.
    public var kinds: [ClipContentKind: Int] = [:]
}

/// Clip totals for the panel's scope chips, counted with the same visibility
/// rules as the panel's own list (no archived or expired clips).
public protocol ScopeCountProviding: Sendable {
    /// Leaves out `excluded`, rows the caller already hides (pending deletes).
    func scopeCounts(excluding excluded: Set<UUID>) async throws -> ScopeCountSnapshot
}

extension GRDBClipboardStore: ScopeCountProviding {
    public func scopeCounts(excluding excluded: Set<UUID>) async throws -> ScopeCountSnapshot {
        var visible = "clip.isArchived = 0 AND \(Self.unexpiredPredicate)"
        var arguments: StatementArguments = [Date.now]
        if !excluded.isEmpty {
            // One bound JSON array, so a bulk delete never hits SQLite's variable limit.
            let ids = excluded.map { "\"\($0.uuidString)\"" }.joined(separator: ",")
            visible += " AND clip.id NOT IN (SELECT value FROM json_each(?))"
            arguments += ["[\(ids)]"]
        }
        return try await writer.read { [visible, arguments] db in
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
            var kinds: [ClipContentKind: Int] = [:]
            let kindRows = try Row.fetchAll(
                db,
                sql: """
                    SELECT clip.kind AS kind, COUNT(*) AS total
                    FROM clip WHERE \(visible)
                    GROUP BY clip.kind
                    """,
                arguments: arguments)
            for row in kindRows {
                let raw: String = row["kind"] ?? ""
                let total: Int = row["total"]
                kinds[ClipContentKind(rawValue: raw) ?? .text, default: 0] += total
            }
            return ScopeCountSnapshot(total: total, boards: boards, kinds: kinds)
        }
    }
}

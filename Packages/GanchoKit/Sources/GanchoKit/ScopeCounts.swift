import Foundation
import GRDB

/// Clip totals for the panel's scope chips, counted with the same visibility
/// rules as the panel's own list (no archived or expired clips).
public protocol ScopeCountProviding: Sendable {
    /// Visible clips per board, keyed by board id; a board with none is absent.
    func visibleCountsByBoard() async throws -> [UUID: Int]
}

extension GRDBClipboardStore: ScopeCountProviding {
    public func visibleCountsByBoard() async throws -> [UUID: Int] {
        try await writer.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT clip_board.boardID AS boardID, COUNT(*) AS total
                    FROM clip_board JOIN clip ON clip.id = clip_board.clipID
                    WHERE clip.isArchived = 0 AND \(Self.unexpiredPredicate)
                    GROUP BY clip_board.boardID
                    """,
                arguments: [Date.now])
            var counts: [UUID: Int] = [:]
            for row in rows {
                guard let id = UUID(uuidString: row["boardID"]) else { continue }
                counts[id] = row["total"]
            }
            return counts
        }
    }
}

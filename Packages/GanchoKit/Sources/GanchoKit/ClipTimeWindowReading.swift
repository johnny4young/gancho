import Foundation
import GRDB

/// The clips first copied around one moment: the session behind a result.
public protocol ClipTimeWindowReading: Sendable {
    /// Visible clips created inside `range`, oldest first. Pinned rows sit at
    /// their own time, not on top.
    func itemsCreated(in range: ClosedRange<Date>, limit: Int) async throws -> [ClipItem]
}

extension ClipTimeWindowReading {
    public func itemsCreated(in range: ClosedRange<Date>) async throws -> [ClipItem] {
        try await itemsCreated(in: range, limit: 200)
    }
}

extension GRDBClipboardStore: ClipTimeWindowReading {
    public func itemsCreated(in range: ClosedRange<Date>, limit: Int) async throws -> [ClipItem] {
        guard limit > 0 else { return [] }
        return try await writer.read { db in
            try ClipRow
                .select(ClipRow.metadataColumns)
                .filter(Column("isArchived") == false)
                .filter(sql: Self.unexpiredPredicate, arguments: [Date.now])
                .filter(Column("createdAt") >= range.lowerBound)
                .filter(Column("createdAt") <= range.upperBound)
                .order(Column("createdAt").asc)
                .limit(limit)
                .fetchAll(db)
                .map(\.item)
        }
    }
}

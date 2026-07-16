import GRDB

extension GRDBClipboardStore {
    /// Shared WHERE clauses for metadata and authorization filters. Keeping
    /// these predicates in SQL ensures excluded rows never consume LIMIT.
    static func appendFilters(
        for query: ClipSearchQuery, to sql: inout String,
        arguments: inout [any DatabaseValueConvertible]
    ) {
        if let kinds = query.kinds, !kinds.isEmpty {
            let placeholders = Array(repeating: "?", count: kinds.count).joined(separator: ",")
            sql += " AND clip.kind IN (\(placeholders))"
            arguments.append(contentsOf: kinds.map(\.rawValue).sorted())
        }
        if let app = query.sourceAppBundleID {
            sql += " AND clip.sourceAppBundleID = ?"
            arguments.append(app)
        }
        if let range = query.dateRange {
            sql += " AND clip.createdAt BETWEEN ? AND ?"
            arguments.append(range.lowerBound)
            arguments.append(range.upperBound)
        }
        if let boardID = query.boardID {
            sql += " AND clip.id IN (SELECT clipID FROM clip_board WHERE boardID = ?)"
            arguments.append(boardID.uuidString)
        }
        if query.markedOnly {
            sql +=
                " AND (clip.isPinned = 1 OR EXISTS "
                + "(SELECT 1 FROM clip_board WHERE clipID = clip.id))"
        }
        if let includedIDs = query.includedIDs {
            guard !includedIDs.isEmpty else {
                sql += " AND 0"
                return
            }
            let rawIDs = includedIDs.map(\.uuidString).sorted()
            let placeholders = Array(repeating: "?", count: rawIDs.count).joined(separator: ",")
            sql += " AND clip.id IN (\(placeholders))"
            arguments.append(contentsOf: rawIDs)
        }
        if query.excludesSensitive {
            sql += " AND clip.isSensitive = 0"
        }
    }
}

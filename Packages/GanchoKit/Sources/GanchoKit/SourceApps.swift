import Foundation
import GRDB

extension GRDBClipboardStore {
    /// Filter-only browsing for an empty search field. This is deliberately a
    /// separate non-FTS query: FTS5 has no meaningful blank MATCH expression,
    /// while app/type/date/board filters still need to compose before typing.
    /// An entirely empty request preserves the historical `search("") == []`
    /// behavior instead of turning search into a second unfiltered list API.
    func filterOnlySearch(_ query: ClipSearchQuery, limit: Int) async throws -> [ClipItem] {
        let hasFilter =
            query.kinds?.isEmpty == false || query.sourceAppBundleID != nil
            || query.dateRange != nil || query.createdBefore != nil || query.deviceName != nil
            || query.boardID != nil
            || query.pinnedOnly || query.markedOnly || query.includedIDs != nil
            || query.excludesSensitive
        guard hasFilter else { return [] }

        return try await writer.read { db in
            var sql = "SELECT \(ClipRow.metadataSelectionSQL) FROM clip WHERE clip.isArchived = 0"
            var arguments: [any DatabaseValueConvertible] = []
            Self.appendFilters(for: query, to: &sql, arguments: &arguments)
            sql += " ORDER BY clip.isPinned DESC, clip.createdAt DESC LIMIT ?"
            arguments.append(limit)
            return try ClipRow.fetchAll(
                db, sql: sql, arguments: StatementArguments(arguments)
            ).map(\.item)
        }
    }

    /// Device names on visible clips, most recent first: the `device:` token's
    /// choices. Names only, never content.
    public func deviceNames(limit: Int = 8) async throws -> [String] {
        guard limit > 0 else { return [] }
        return try await writer.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT sourceDeviceName FROM clip
                    WHERE isArchived = 0 AND sourceDeviceName IS NOT NULL
                      AND TRIM(sourceDeviceName) <> ''
                    GROUP BY sourceDeviceName
                    ORDER BY MAX(createdAt) DESC, sourceDeviceName ASC
                    LIMIT ?
                    """,
                arguments: [limit])
        }
    }

    /// Recent source apps represented in visible history, with aggregate clip
    /// counts. The query selects only bundle IDs, counts, and recency metadata;
    /// clipboard content never enters the discovery path.
    public func recentSourceApps(limit: Int = 8) async throws -> [ClipSourceApp] {
        guard limit > 0 else { return [] }
        return try await writer.read { db in
            let rows = try Row.fetchAll(
                db,
                sql: """
                    SELECT sourceAppBundleID AS bundleID, COUNT(*) AS clipCount,
                           MAX(createdAt) AS mostRecentCapture
                    FROM clip
                    WHERE isArchived = 0
                      AND sourceAppBundleID IS NOT NULL
                      AND TRIM(sourceAppBundleID) <> ''
                    GROUP BY sourceAppBundleID
                    ORDER BY mostRecentCapture DESC, bundleID ASC
                    LIMIT ?
                    """,
                arguments: [limit])
            return rows.compactMap { row in
                guard let bundleID: String = row["bundleID"] else { return nil }
                let clipCount: Int = row["clipCount"]
                return ClipSourceApp(bundleID: bundleID, clipCount: clipCount)
            }
        }
    }
}

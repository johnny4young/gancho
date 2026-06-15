import Foundation
import GRDB

/// GRDB-backed MCP support: the production `MCPClipStore` conformance plus the
/// access log the Privacy Center reads. The log table is created by the
/// `v9-mcp-access-log` migration in `GRDBClipboardStore`.
extension GRDBClipboardStore: MCPClipStore {
    /// Single-clip metadata fetch (membership/sensitive checks, get_clip
    /// without paging the blob). `content(for:)` remains the only blob load.
    public func item(id: UUID) async throws -> ClipItem? {
        try await writer.read { db in
            try ClipRow.filter(key: id.uuidString).fetchOne(db)?.item
        }
    }

    // MARK: - MCP access log (Privacy Center)

    /// Appends one access record. Metadata only — the column set cannot hold
    /// content, so a logging bug can never leak a clip.
    public func recordMCPAccess(_ event: MCPAccessEvent) async throws {
        try await writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO mcp_access_log (occurredAt, tool, scope, resultCount, wasDenied)
                    VALUES (?, ?, ?, ?, ?)
                    """,
                arguments: [
                    event.occurredAt, event.tool.rawValue, event.scope.rawValue,
                    event.resultCount, event.wasDenied,
                ])
        }
    }

    /// Most recent MCP/CLI accesses, newest first — the Privacy Center feed.
    public func recentMCPAccesses(limit: Int = 50) async throws -> [MCPAccessEvent] {
        try await writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT occurredAt, tool, scope, resultCount, wasDenied
                    FROM mcp_access_log ORDER BY occurredAt DESC, id DESC LIMIT ?
                    """,
                arguments: [limit]
            ).compactMap { row in
                guard let tool = MCPToolName(rawValue: row["tool"]),
                    let scope = MCPAccessScope(rawValue: row["scope"])
                else { return nil }
                return MCPAccessEvent(
                    tool: tool, scope: scope, resultCount: row["resultCount"],
                    wasDenied: row["wasDenied"], occurredAt: row["occurredAt"])
            }
        }
    }
}

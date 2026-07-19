import Foundation
import GRDB

/// GRDB-backed MCP support: the production `MCPClipStore` conformance plus the
/// access log the Privacy Center reads. v9 created the content-free table and
/// v19 added client/grant policy metadata.
extension GRDBClipboardStore: MCPClipStore {
    /// Kept with the MCP adapter rather than the core store migrations so the
    /// ledger schema and its row mapping evolve together.
    static func registerMCPClientLedgerMigration(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v19-mcp-client-ledger") { db in
            // Client/grant identity and policy outcome only. These optional
            // columns preserve every v9 row while making revoke/expiry and
            // read-only denials explainable without storing request content.
            try db.alter(table: "mcp_access_log") { table in
                table.add(column: "grantID", .text)
                table.add(column: "clientName", .text)
                table.add(column: "accessMode", .text)
                table.add(column: "denialReason", .text)
            }
            try db.create(
                index: "idx_mcp_access_log_grant_time",
                on: "mcp_access_log",
                columns: ["grantID", "occurredAt"])
        }
    }

    /// Single-clip metadata fetch (membership/sensitive checks, get_clip
    /// without paging the blob). `content(for:)` remains the only blob load.
    public func item(id: UUID) async throws -> ClipItem? {
        try await writer.read { db in
            try ClipRow.filter(key: id.uuidString).fetchOne(db)?.item
        }
    }

    public func boardIDs(for clipID: UUID) async throws -> Set<UUID> {
        try await writer.read { db in
            let rawIDs = try String.fetchAll(
                db,
                sql: "SELECT boardID FROM clip_board WHERE clipID = ?",
                arguments: [clipID.uuidString])
            return Set(rawIDs.compactMap(UUID.init(uuidString:)))
        }
    }

    // MARK: - MCP access log (Privacy Center)

    /// Appends one access record. Metadata only — the column set cannot hold
    /// content, so a logging bug can never leak a clip.
    public func recordMCPAccess(_ event: MCPAccessEvent) async throws {
        try await writer.write { db in
            try db.execute(
                sql: """
                    INSERT INTO mcp_access_log (
                        occurredAt, tool, scope, accessMode, grantID, clientName,
                        resultCount, wasDenied, denialReason
                    ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
                    """,
                arguments: [
                    event.occurredAt, event.tool.rawValue, event.scope.rawValue,
                    event.accessMode?.rawValue, event.grantID?.uuidString, event.clientName,
                    event.resultCount, event.wasDenied, event.denialReason?.rawValue
                ])
        }
    }

    /// Most recent MCP/CLI accesses, newest first — the Privacy Center feed.
    public func recentMCPAccesses(limit: Int = 50) async throws -> [MCPAccessEvent] {
        try await writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT occurredAt, tool, scope, accessMode, grantID, clientName,
                           resultCount, wasDenied, denialReason
                    FROM mcp_access_log ORDER BY occurredAt DESC, id DESC LIMIT ?
                    """,
                arguments: [limit]
            ).compactMap { row in
                guard let tool = MCPToolName(rawValue: row["tool"]),
                    let scope = MCPAccessScope(rawValue: row["scope"])
                else { return nil }
                let accessModeRaw: String? = row["accessMode"]
                let grantIDRaw: String? = row["grantID"]
                let clientName: String? = row["clientName"]
                let denialReasonRaw: String? = row["denialReason"]
                return MCPAccessEvent(
                    tool: tool,
                    scope: scope,
                    accessMode: accessModeRaw.flatMap(MCPAccessMode.init(rawValue:)),
                    grantID: grantIDRaw.flatMap(UUID.init(uuidString:)),
                    clientName: clientName,
                    resultCount: row["resultCount"],
                    wasDenied: row["wasDenied"],
                    denialReason: denialReasonRaw.flatMap(MCPAccessDenialReason.init(rawValue:)),
                    occurredAt: row["occurredAt"])
            }
        }
    }
}

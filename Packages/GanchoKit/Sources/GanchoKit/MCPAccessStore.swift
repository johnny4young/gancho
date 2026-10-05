import Foundation
import GRDB

/// GRDB-backed MCP support: the production `MCPClipStore` conformance plus the
/// access log the Privacy Center reads. v9 created the content-free table and
/// v19 added client/grant policy metadata.
extension GRDBClipboardStore: MCPClipStore {
    private enum MCPRowRead: Sendable {
        case finished(MCPClipReadResult)
        case payload(ClipRow)
    }

    public func readForMCP(
        id: UUID, grant: MCPClientGrant, requiresContextPack: Bool, now: Date
    ) async throws -> MCPClipReadResult {
        // GRDB keeps every query in this read closure on one database snapshot.
        // A later text edit, sensitivity change or board removal cannot mix its
        // payload with authorization metadata from an earlier generation.
        let snapshot = try await writer.read { db -> MCPRowRead in
            let request = ClipRow.select(ClipRow.metadataColumns)
                .filter(key: id.uuidString)
                .filter(Column("isArchived") == false)
                .filter(sql: Self.unexpiredPredicate, arguments: [now])
            guard let row = try request.fetchOne(db) else { return .finished(.missing) }
            let item = row.item
            var boardIDs: Set<UUID> = []
            if grant.contextPack?.boardID != nil || grant.scope == .boards {
                let rawIDs = try String.fetchAll(
                    db, sql: "SELECT boardID FROM clip_board WHERE clipID = ?",
                    arguments: [id.uuidString])
                boardIDs = Set(rawIDs.compactMap(UUID.init(uuidString:)))
            }
            if let pack = grant.contextPack, pack.isExplicit {
                guard pack.contains(item: item, boardIDs: boardIDs, now: now) else {
                    return .finished(.outsideContext)
                }
            } else if requiresContextPack {
                return .finished(.outsideContext)
            }
            if ClipSafePresentation.requiresMasking(item) { return .finished(.sensitive) }
            if grant.scope == .metadata
                || (grant.scope == .boards && !item.isPinned && boardIDs.isEmpty)
            {
                return .finished(.metadata(item))
            }
            // Only an authorized content read selects payload columns. The row
            // is captured before leaving the same policy/membership snapshot.
            guard let payload = try ClipRow.filter(key: id.uuidString).fetchOne(db) else {
                return .finished(.missing)
            }
            return .payload(payload)
        }
        switch snapshot {
        case .finished(let result): return result
        case .payload(let row): return .content(row.item, try content(from: row))
        }
    }

    /// Kept with the MCP adapter rather than the core store migrations so the
    /// ledger schema and its row mapping evolve together.
    static func registerMCPClientLedgerMigration(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration(
            GanchoDatabaseMigrator.Identifier.mcpClientLedger.rawValue
        ) { db in
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

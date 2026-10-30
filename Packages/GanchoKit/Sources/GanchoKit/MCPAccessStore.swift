import Foundation
import GRDB

/// GRDB-backed MCP support: the production `MCPClipStore` conformance plus the
/// access log the Privacy Center reads. v9 created the content-free table and
/// v19 added client/grant policy metadata.
extension GRDBClipboardStore: MCPClipStore {
    private enum MCPRowRead: Sendable {
        case finished(MCPClipReadResult)
        case payload(ClipRow)
        case reviewed(ClipItem, recognizedText: String?)
    }

    private enum ReviewedShareCheck {
        case original, refused
        case reviewed(recognizedText: String?)
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
                boardIDs = try Self.boardIDs(forClip: id, in: db)
            }
            if let pack = grant.contextPack, pack.isExplicit {
                guard pack.contains(item: item, boardIDs: boardIDs, now: now) else {
                    return .finished(.outsideContext)
                }
            } else if requiresContextPack {
                return .finished(.outsideContext)
            }
            let shares = try Self.checkReviewedShares(
                of: item, grant.contextPack?.representations(of: id) ?? [], in: db)
            if case .refused = shares { return .finished(.outsideContext) }
            if ClipSafePresentation.requiresMasking(item) { return .finished(.sensitive) }
            if Self.withholdsBody(grant, item, boardIDs) { return .finished(.metadata(item)) }
            if case .reviewed(let text) = shares { return .reviewed(item, recognizedText: text) }
            // Only an authorized content read selects payload columns. The row
            // is captured before leaving the same policy/membership snapshot.
            guard let payload = try ClipRow.filter(key: id.uuidString).fetchOne(db) else {
                return .finished(.missing)
            }
            return .payload(payload)
        }
        return try resolve(snapshot, image: grant.contextPack?.reviewedImage(of: id))
    }

    /// Payload files are read after the snapshot closes, by the identity it captured.
    private func resolve(
        _ snapshot: MCPRowRead, image: MCPReviewedImage?
    ) throws -> MCPClipReadResult {
        switch snapshot {
        case .finished(let result): return result
        case .payload(let row): return .content(row.item, try content(from: row))
        case .reviewed(let item, let text):
            return .reviewed(item, recognizedText: text, image: image.flatMap(reviewedImageData))
        }
    }

    private static func withholdsBody(
        _ grant: MCPClientGrant, _ item: ClipItem, _ boardIDs: Set<UUID>
    ) -> Bool {
        grant.scope == .metadata
            || (grant.scope == .boards && !item.isPinned && boardIDs.isEmpty)
    }

    /// Reviewed shares cover one image only. Re-recognition rewrites its text
    /// without a new revision, so the text itself is compared inside the
    /// caller's snapshot; the image's pixels are pinned by the clip revision.
    private static func checkReviewedShares(
        of item: ClipItem, _ shares: [MCPClipRepresentation], in db: Database
    ) throws -> ReviewedShareCheck {
        guard !shares.isEmpty else { return .original }
        guard item.kind == .image else { return .refused }
        let textShare = shares.first { $0.reviewedImage == nil }
        guard let textShare else { return .reviewed(recognizedText: nil) }
        guard
            let text = try String.fetchOne(
                db, sql: "SELECT contentText FROM clip WHERE id = ?",
                arguments: [item.id.uuidString]),
            textShare.authorizes(recognizedText: text)
        else { return .refused }
        return .reviewed(recognizedText: text)
    }

    /// The derivative is read by its digest and checked again: a missing,
    /// damaged or substituted file is withheld, never replaced by the original.
    private func reviewedImageData(_ image: MCPReviewedImage) -> Data? {
        guard let data = try? blobsForMaintenance.reviewedImages.read(hash: image.sha256),
            image.authorizes(data)
        else { return nil }
        return data
    }

    /// Stores a reviewed derivative so a grant can serve exactly these bytes.
    public func saveReviewedImage(_ derivative: ReviewedImageDerivative) throws {
        try blobsForMaintenance.reviewedImages.write(derivative.data)
    }

    /// Deletes reviewed derivatives that no live grant references.
    @discardableResult
    public func removeReviewedImages(except referenced: Set<String>) -> Int {
        blobsForMaintenance.reviewedImages.removeAll(except: referenced)
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

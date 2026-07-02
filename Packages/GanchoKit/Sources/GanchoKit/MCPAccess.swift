import Foundation

/// How much of the history a local MCP/CLI client may see. The access
/// boundary is about EXPOSURE, not read/write: a more restrictive scope
/// reveals less clip data, never fewer verbs.
///
/// - `metadata`: titles and sanitized previews only — never a content body.
///   The agent can find clips and pin them, but cannot read what they hold.
/// - `boards`: full content, but only for clips the user has deliberately
///   marked (pinned / on a board). Raw history stays invisible.
/// - `all`: full content of every non-sensitive clip.
///
/// Sensitive clips (`isSensitive`) are vetoed in EVERY scope, including
/// `all` — an automated agent never sees secrets the detector flagged.
public enum MCPAccessScope: String, Sendable, Codable, CaseIterable {
    case metadata
    case boards
    case all
}

/// The five tools the local server exposes. Raw values are the wire names
/// MCP clients call; the enum keeps the access log and scope checks honest.
public enum MCPToolName: String, Sendable, Codable, CaseIterable {
    case searchClips = "search_clips"
    case getClip = "get_clip"
    case createPin = "create_pin"
    case pasteStack = "paste_stack"
    case listBoards = "list_boards"
}

/// One MCP/CLI access, recorded for the Privacy Center. Metadata only by
/// construction: which tool ran, under what scope, how many clips it
/// exposed, and whether the scope denied it — NEVER any clip content.
public struct MCPAccessEvent: Sendable, Equatable, Codable {
    public var tool: MCPToolName
    public var scope: MCPAccessScope
    /// How many clips the call exposed (0 for writes, denials, empty results).
    public var resultCount: Int
    /// The scope (or the sensitive veto) refused the call.
    public var wasDenied: Bool
    public var occurredAt: Date

    public init(
        tool: MCPToolName, scope: MCPAccessScope, resultCount: Int = 0,
        wasDenied: Bool = false, occurredAt: Date = .now
    ) {
        self.tool = tool
        self.scope = scope
        self.resultCount = resultCount
        self.wasDenied = wasDenied
        self.occurredAt = occurredAt
    }
}

/// On-disk switch for the local MCP server. Lives as a small JSON file in the
/// store directory (not UserDefaults) precisely so the non-sandboxed `gancho`
/// binary and the app read the SAME state without an entitlements dance. A
/// missing file means OFF — the feature is opt-in by absence.
public struct MCPServerConfig: Sendable, Equatable, Codable {
    public var isEnabled: Bool
    public var scope: MCPAccessScope

    public init(isEnabled: Bool = false, scope: MCPAccessScope = .metadata) {
        self.isEnabled = isEnabled
        self.scope = scope
    }

    /// True when the scope exposes clip CONTENT (`boards` or `all`) rather
    /// than metadata-only previews. This file is plaintext, so any local
    /// process can raise the scope — callers surface elevation prominently
    /// (the CLI flags it on server start) instead of gating on it.
    public var isElevated: Bool { scope != .metadata }

    public static let fileName = "mcp-config.json"

    /// Loads the config from a store directory; OFF/metadata when the file is
    /// missing or unreadable (fail safe — never serve by accident).
    public static func load(fromStoreDirectory directory: URL) -> MCPServerConfig {
        let url = directory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url),
            let config = try? JSONDecoder().decode(MCPServerConfig.self, from: data)
        else {
            return MCPServerConfig()
        }
        return config
    }

    /// Persists the config atomically so a concurrent read never sees a
    /// half-written file.
    public func save(toStoreDirectory directory: URL) throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(self)
        try data.write(to: directory.appendingPathComponent(Self.fileName), options: .atomic)
    }
}

/// The narrow store surface the MCP tools need. Defined here (not in
/// GanchoMCP) so the production conformance lives with `GRDBClipboardStore`
/// in this module — no retroactive conformance across the package boundary.
public protocol MCPClipStore: Sendable {
    func search(_ query: ClipSearchQuery, limit: Int) async throws -> [ClipItem]
    func item(id: UUID) async throws -> ClipItem?
    func content(for id: UUID) async throws -> ClipContent?
    func setPinned(id: UUID, _ pinned: Bool) async throws
    func pinboards() async throws -> [Pinboard]
    @discardableResult
    func createPinboard(name: String, sfSymbol: String) async throws -> Pinboard
    func assign(clipID: UUID, toBoard boardID: UUID) async throws
}

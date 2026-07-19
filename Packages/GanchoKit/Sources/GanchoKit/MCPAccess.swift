import Foundation

/// How much clip data an MCP client may see. Exposure and mutation are
/// independent: ``MCPAccessMode`` controls writes, while this scope controls
/// the shape and breadth of reads.
public enum MCPAccessScope: String, Sendable, Codable, CaseIterable {
    /// Titles and sanitized previews only — never a content body.
    case metadata
    /// Full content only for clips the user deliberately marked (pinned or on
    /// at least one board).
    case boards
    /// Full content for every non-sensitive clip inside the client's context
    /// pack.
    case all
}

/// Whether a client can only inspect its context or also perform Gancho's
/// narrow organization mutation (`create_pin`). Read-only is the safe default.
public enum MCPAccessMode: String, Sendable, Codable, CaseIterable {
    case readOnly = "read-only"
    case readWrite = "read-write"

    public var allowsWrites: Bool { self == .readWrite }
}

/// Relative time fence applied on every tool call. The bound is recomputed at
/// call time so a long-running MCP process never keeps yesterday's window.
public enum MCPTimeScope: String, Sendable, Codable, CaseIterable {
    case lastHour = "last-hour"
    case lastDay = "last-day"
    case lastWeek = "last-week"
    case lastMonth = "last-month"
    case allTime = "all-time"

    public func lowerBound(relativeTo now: Date) -> Date? {
        let interval: TimeInterval? =
            switch self {
            case .lastHour: 60 * 60
            case .lastDay: 24 * 60 * 60
            case .lastWeek: 7 * 24 * 60 * 60
            case .lastMonth: 30 * 24 * 60 * 60
            case .allTime: nil
            }
        return interval.map { now.addingTimeInterval(-$0) }
    }
}

/// Explicit local context exposed to one client. A pack selects either one
/// board or a curated set of clip ids, optionally narrowed by a rolling time
/// window. It never represents ambient history.
public struct MCPContextPack: Sendable, Equatable, Codable {
    public static let maximumCuratedClipCount = 500

    public var name: String
    public var boardID: UUID?
    public var boardName: String?
    public var clipIDs: Set<UUID>
    public var timeScope: MCPTimeScope

    public init(
        name: String,
        boardID: UUID? = nil,
        boardName: String? = nil,
        clipIDs: Set<UUID> = [],
        timeScope: MCPTimeScope = .allTime
    ) {
        self.name = name
        self.boardID = boardID
        self.boardName = boardName
        self.clipIDs = clipIDs
        self.timeScope = timeScope
    }

    public var isExplicit: Bool {
        (boardID != nil || !clipIDs.isEmpty) && clipIDs.count <= Self.maximumCuratedClipCount
    }

    public func contains(
        item: ClipItem,
        boardIDs: Set<UUID>,
        now: Date
    ) -> Bool {
        guard isExplicit else { return false }
        if let lowerBound = timeScope.lowerBound(relativeTo: now), item.createdAt < lowerBound {
            return false
        }
        if let boardID, !boardIDs.contains(boardID) { return false }
        if !clipIDs.isEmpty, !clipIDs.contains(item.id) { return false }
        return true
    }
}

/// One user-approved client identity. Revocation is retained instead of
/// deleting the grant so the UI and ledger can explain why later calls failed.
public struct MCPClientGrant: Identifiable, Sendable, Equatable, Codable {
    public static let maximumClientNameLength = 80

    public var id: UUID
    public var clientName: String
    public var scope: MCPAccessScope
    public var accessMode: MCPAccessMode
    public var contextPack: MCPContextPack?
    public var createdAt: Date
    public var expiresAt: Date?
    public var revokedAt: Date?

    public init(
        id: UUID = UUID(),
        clientName: String,
        scope: MCPAccessScope = .metadata,
        accessMode: MCPAccessMode = .readOnly,
        contextPack: MCPContextPack? = nil,
        createdAt: Date = .now,
        expiresAt: Date? = nil,
        revokedAt: Date? = nil
    ) {
        self.id = id
        self.clientName = clientName
        self.scope = scope
        self.accessMode = accessMode
        self.contextPack = contextPack
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.revokedAt = revokedAt
    }

    public func state(at now: Date = .now) -> MCPGrantState {
        if revokedAt != nil { return .revoked }
        if let expiresAt, expiresAt <= now { return .expired }
        return .active
    }

    /// Bounded, non-empty identity used in UI and the content-free ledger.
    /// Config files are local but can still be edited by hand; never let an
    /// unbounded label inflate a row or become an invisible client.
    public var safeClientName: String {
        let printable = clientName.unicodeScalars.map { scalar in
            CharacterSet.controlCharacters.contains(scalar) ? " " : String(scalar)
        }.joined()
        let singleLine =
            printable
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        let bounded = String(singleLine.prefix(Self.maximumClientNameLength))
        return bounded.isEmpty ? String(localized: "Unknown client") : bounded
    }
}

public enum MCPGrantState: String, Sendable, Codable {
    case active
    case expired
    case revoked
}

/// Stable denial categories for the content-free access ledger.
public enum MCPAccessDenialReason: String, Sendable, Codable {
    case serverDisabled = "server-disabled"
    case grantMissing = "grant-missing"
    case grantExpired = "grant-expired"
    case grantRevoked = "grant-revoked"
    case readOnly = "read-only"
    case outsideContext = "outside-context"
    case scope
    case sensitive
    case invalidArguments = "invalid-arguments"
    case toolFailure = "tool-failure"
}

/// Result of resolving the selected grant from the live config file.
public enum MCPGrantResolution: Sendable, Equatable {
    case active(MCPClientGrant)
    case disabled(MCPClientGrant?)
    case missing
    case invalidContext(MCPClientGrant)
    case expired(MCPClientGrant)
    case revoked(MCPClientGrant)

    public var grant: MCPClientGrant? {
        switch self {
        case .active(let grant), .disabled(let grant?), .invalidContext(let grant),
            .expired(let grant), .revoked(let grant):
            grant
        case .disabled(nil), .missing:
            nil
        }
    }

    public var denialReason: MCPAccessDenialReason? {
        switch self {
        case .active: nil
        case .disabled: .serverDisabled
        case .missing: .grantMissing
        case .invalidContext: .outsideContext
        case .expired: .grantExpired
        case .revoked: .grantRevoked
        }
    }
}

/// The five tools the local server exposes. Raw values are the wire names
/// MCP clients call; the enum keeps authorization and ledger rows honest.
public enum MCPToolName: String, Sendable, Codable, CaseIterable {
    case searchClips = "search_clips"
    case getClip = "get_clip"
    case createPin = "create_pin"
    case pasteStack = "paste_stack"
    case listBoards = "list_boards"

    public var mutatesStore: Bool { self == .createPin }
}

/// One MCP/CLI access, recorded for the Privacy Center. Metadata only by
/// construction: client/grant identifiers, tool, policy, count, and denial.
/// No field can hold a clip title, query, body, source app, path, or hash.
public struct MCPAccessEvent: Sendable, Equatable, Codable {
    public var tool: MCPToolName
    public var scope: MCPAccessScope
    public var accessMode: MCPAccessMode?
    public var grantID: UUID?
    public var clientName: String?
    /// How many clips the call exposed (0 for writes, denials, empty results).
    public var resultCount: Int
    public var wasDenied: Bool
    public var denialReason: MCPAccessDenialReason?
    public var occurredAt: Date

    public init(
        tool: MCPToolName,
        scope: MCPAccessScope,
        accessMode: MCPAccessMode? = nil,
        grantID: UUID? = nil,
        clientName: String? = nil,
        resultCount: Int = 0,
        wasDenied: Bool = false,
        denialReason: MCPAccessDenialReason? = nil,
        occurredAt: Date = .now
    ) {
        self.tool = tool
        self.scope = scope
        self.accessMode = accessMode
        self.grantID = grantID
        self.clientName = clientName
        self.resultCount = resultCount
        self.wasDenied = wasDenied
        self.denialReason = denialReason
        self.occurredAt = occurredAt
    }
}

/// Shared local MCP authorization state. The config contains no token or clip
/// content. A missing/unreadable file means OFF, and a server must select a
/// concrete grant id before it can advertise or call tools.
public struct MCPServerConfig: Sendable, Equatable, Codable {
    public static let currentSchemaVersion = 2
    public static let fileName = "mcp-config.json"

    public var schemaVersion: Int
    public var isEnabled: Bool
    /// Retained for decoding the v1 global config. New calls use each grant's
    /// own scope and never fall back to this value.
    public var scope: MCPAccessScope
    public var grants: [MCPClientGrant]

    public init(
        isEnabled: Bool = false,
        scope: MCPAccessScope = .metadata,
        grants: [MCPClientGrant] = []
    ) {
        schemaVersion = Self.currentSchemaVersion
        self.isEnabled = isEnabled
        self.scope = scope
        self.grants = grants
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, isEnabled, scope, grants
    }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decodeIfPresent(Int.self, forKey: .schemaVersion) ?? 1
        isEnabled = try values.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? false
        scope = try values.decodeIfPresent(MCPAccessScope.self, forKey: .scope) ?? .metadata
        grants = try values.decodeIfPresent([MCPClientGrant].self, forKey: .grants) ?? []

        // A v1 file authorized every local client globally, while a future
        // schema may carry invariants this build cannot enforce. Neither can
        // be interpreted as a usable v2 policy.
        if schemaVersion != Self.currentSchemaVersion {
            isEnabled = false
            grants = []
            schemaVersion = Self.currentSchemaVersion
        }
    }

    public func resolveGrant(id: UUID?, at now: Date = .now) -> MCPGrantResolution {
        guard let id, let grant = grants.first(where: { $0.id == id }) else { return .missing }
        guard isEnabled else { return .disabled(grant) }
        switch grant.state(at: now) {
        case .active:
            guard grant.contextPack?.isExplicit == true else { return .invalidContext(grant) }
            return .active(grant)
        case .expired: return .expired(grant)
        case .revoked: return .revoked(grant)
        }
    }

    public var activeGrants: [MCPClientGrant] {
        grants.filter { $0.state() == .active && $0.contextPack?.isExplicit == true }
    }

    /// Compatibility summary for callers that only need a warning badge. v2
    /// grants are authoritative; the legacy global scope is consulted only
    /// while no grants exist.
    public var isElevated: Bool {
        if grants.isEmpty { return scope != .metadata }
        return activeGrants.contains { $0.scope != .metadata }
    }

    public static func load(fromStoreDirectory directory: URL) -> MCPServerConfig {
        let url = directory.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url),
            let config = try? JSONDecoder().decode(MCPServerConfig.self, from: data)
        else {
            return MCPServerConfig()
        }
        return config
    }

    /// Persists atomically and owner-only. The grant ids are authorization
    /// selectors rather than secrets, but other local users still have no
    /// reason to inspect them.
    public func save(toStoreDirectory directory: URL) throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(Self.fileName)
        let data = try JSONEncoder().encode(self)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

/// The narrow store surface MCP tools need. `boardIDs` makes both broad
/// marked-content scope and one-board context packs exact without N+1 searches.
public protocol MCPClipStore: Sendable {
    func search(_ query: ClipSearchQuery, limit: Int) async throws -> [ClipItem]
    func item(id: UUID) async throws -> ClipItem?
    func content(for id: UUID) async throws -> ClipContent?
    func boardIDs(for clipID: UUID) async throws -> Set<UUID>
    func setPinned(id: UUID, _ pinned: Bool) async throws
    func pinboards() async throws -> [Pinboard]
    @discardableResult
    func createPinboard(name: String, sfSymbol: String) async throws -> Pinboard
    func assign(clipID: UUID, toBoard boardID: UUID) async throws
}

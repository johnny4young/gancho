import CryptoKit
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
    /// The reviewed ``ClipItem/contextRevision`` per clip id (uuidString keys).
    /// When present, a clip changed after review is outside the pack. Nil for
    /// packs that predate revision binding.
    public var clipRevisions: [String: String]?
    /// What was reviewed per clip id (uuidString keys). A missing or empty
    /// entry, or a pack that predates representations, means the original.
    public var clipRepresentations: [String: [MCPClipRepresentation]]?

    public init(
        name: String,
        boardID: UUID? = nil,
        boardName: String? = nil,
        clipIDs: Set<UUID> = [],
        timeScope: MCPTimeScope = .allTime,
        clipRevisions: [String: String]? = nil,
        clipRepresentations: [String: [MCPClipRepresentation]]? = nil
    ) {
        self.name = name
        self.boardID = boardID
        self.boardName = boardName
        self.clipIDs = clipIDs
        self.timeScope = timeScope
        self.clipRevisions = clipRevisions
        self.clipRepresentations = clipRepresentations
    }

    /// Empty means the clip's own content.
    public func representations(of id: UUID) -> [MCPClipRepresentation] {
        clipRepresentations?[id.uuidString] ?? []
    }

    public func sharesRecognizedText(of id: UUID) -> Bool {
        representations(of: id).contains { $0.reviewedImage == nil }
    }

    public func reviewedImage(of id: UUID) -> MCPReviewedImage? {
        representations(of: id).lazy.compactMap(\.reviewedImage).first
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
        return isReviewedRevision(item)
    }

    /// Whether `item` is still the revision the user reviewed. Packs that
    /// predate revision binding accept every revision.
    public func isReviewedRevision(_ item: ClipItem) -> Bool {
        guard let clipRevisions else { return true }
        return clipRevisions[item.id.uuidString] == item.contextRevision
    }
}

/// One reviewed derivative of an image that a selected-context grant shares
/// in place of the clip's own content. Each is authorized on its own.
public enum MCPClipRepresentation: Sendable, Equatable, Codable {
    /// The text recognized from the image, only while it still hashes to the
    /// reviewed value.
    case recognizedText(sha256: String)
    /// The exact resampled, metadata-free pixels the user reviewed.
    case reviewedImage(MCPReviewedImage)

    public static func recognizedText(reviewing text: String) -> MCPClipRepresentation {
        .recognizedText(sha256: digest(of: Data(text.utf8)))
    }

    public func authorizes(recognizedText text: String) -> Bool {
        guard case .recognizedText(let sha256) = self else { return false }
        return sha256 == Self.digest(of: Data(text.utf8))
    }

    public var reviewedImage: MCPReviewedImage? {
        guard case .reviewedImage(let image) = self else { return nil }
        return image
    }

    static func digest(of data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

/// Identity of a reviewed image derivative. `sha256` also names its file in
/// the store's reviewed-image directory.
public struct MCPReviewedImage: Sendable, Equatable, Codable {
    public let sha256: String
    public let mimeType: String
    public let width: Int
    public let height: Int
    public let byteCount: Int

    public init(_ derivative: ReviewedImageDerivative) {
        sha256 = derivative.sha256
        mimeType = derivative.mimeType
        width = derivative.width
        height = derivative.height
        byteCount = derivative.data.count
    }

    public func authorizes(_ data: Data) -> Bool {
        data.count == byteCount && MCPClipRepresentation.digest(of: data) == sha256
    }
}

/// Reviewed derivatives live outside clip rows, so their owner keeps them only
/// while a grant can still serve them.
public protocol ReviewedImageStoring: Sendable {
    func saveReviewedImage(_ derivative: ReviewedImageDerivative) throws
    @discardableResult
    func removeReviewedImages(except referenced: Set<String>) -> Int
}

extension GRDBClipboardStore: ReviewedImageStoring {}

extension MCPServerConfig {
    /// Digests of the reviewed images an active grant can still serve.
    public func liveReviewedImages(at now: Date = .now) -> Set<String> {
        Set(
            grants.filter { $0.state(at: now) == .active }.flatMap { grant in
                (grant.contextPack?.clipRepresentations ?? [:]).values.joined()
                    .compactMap(\.reviewedImage?.sha256)
            })
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
    ///
    /// The staging step is what makes "atomically" true of the PERMISSIONS as
    /// well as the bytes. Writing the file and then chmod-ing it means a failed
    /// chmod throws AFTER the new authorization state is already readable by
    /// the CLI and the MCP server — so the caller reports a failed save, keeps
    /// the old config in memory, and the two disagree about who is allowed in.
    /// The file could also keep default permissions. Creating the replacement
    /// owner-only from the start and moving it into place with `rename(2)`
    /// leaves exactly two possible states on disk: the previous file, or the
    /// complete new one with the right mode.
    public func save(toStoreDirectory directory: URL) throws {
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(Self.fileName)
        let data = try JSONEncoder().encode(self)
        let staged = directory.appendingPathComponent(".\(Self.fileName).\(UUID().uuidString)")
        guard
            FileManager.default.createFile(
                atPath: staged.path, contents: data,
                attributes: [.posixPermissions: 0o600])
        else {
            throw CocoaError(.fileWriteUnknown)
        }
        try AtomicFileReplace.publish(staged: staged, as: url)
    }
}

/// One authorization and content result from a consistent store snapshot.
public enum MCPClipReadResult: Sendable, Equatable {
    case missing
    case outsideContext
    case sensitive
    case metadata(ClipItem)
    case content(ClipItem, ClipContent?)
    /// Reviewed derivatives of an image clip, in place of its content. A nil
    /// image means one was granted but its file is gone or no longer matches.
    case reviewed(ClipItem, recognizedText: String?, image: Data?)
}

/// The narrow store surface MCP tools need. Per-clip reads go only through
/// ``readForMCP(id:grant:requiresContextPack:now:)``; there is deliberately no
/// separate content or board-membership read to compose with a policy check.
public protocol MCPClipStore: Sendable {
    func search(_ query: ClipSearchQuery, limit: Int) async throws -> [ClipItem]
    func item(id: UUID) async throws -> ClipItem?
    /// Visible rows only: archived and expired ids are omitted.
    func items(ids: [UUID]) async throws -> [ClipItem]
    /// Policy metadata, board membership and text must come from one database
    /// snapshot. Implementations must not compose separately awaited reads.
    func readForMCP(
        id: UUID, grant: MCPClientGrant, requiresContextPack: Bool, now: Date
    ) async throws -> MCPClipReadResult
    func setPinned(id: UUID, _ pinned: Bool) async throws
    func pinboards() async throws -> [Pinboard]
    @discardableResult
    func createPinboard(name: String, sfSymbol: String) async throws -> Pinboard
    func assign(clipID: UUID, toBoard boardID: UUID) async throws
}

extension ClipItem {
    /// Identifies the reviewed state of a clip for selected-context grants.
    /// Text edits keep `contentHash` (edits are curation) but always advance
    /// `updatedAt`, stored to the millisecond, so both take part.
    public var contextRevision: String {
        "\(contentHash)@\(Int64((updatedAt.timeIntervalSince1970 * 1_000).rounded()))"
    }
}

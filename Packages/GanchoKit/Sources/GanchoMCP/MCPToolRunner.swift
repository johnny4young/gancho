import Foundation
import GanchoKit

/// Runs MCP tools against a live, per-client grant. Authorization is resolved
/// before every call, so disabling MCP, expiry, or one-click revoke affects an
/// already-running stdio process without restart.
public struct MCPToolRunner: Sendable {
    private let store: any MCPClipStore
    private let grantProvider: @Sendable () async -> MCPGrantResolution
    private let log: @Sendable (MCPAccessEvent) async -> Void
    private let now: @Sendable () -> Date
    private let requiresContextPack: Bool

    /// Static-policy convenience for focused tests and embedded callers. The
    /// production CLI uses the live grant-provider initializer below. `accessMode`
    /// defaults to `.readOnly` — least privilege by default, so an embedded
    /// caller that omits it can never silently gain write access; a caller that
    /// needs writes must ask for `.readWrite` explicitly.
    public init(
        store: any MCPClipStore,
        scope: MCPAccessScope,
        accessMode: MCPAccessMode = .readOnly,
        log: @escaping @Sendable (MCPAccessEvent) async -> Void = { _ in }
    ) {
        let grant = MCPClientGrant(
            clientName: "Embedded client", scope: scope, accessMode: accessMode)
        self.init(
            store: store,
            grantProvider: { .active(grant) },
            log: log,
            requiresContextPack: false)
    }

    public init(
        store: any MCPClipStore,
        grantProvider: @escaping @Sendable () async -> MCPGrantResolution,
        log: @escaping @Sendable (MCPAccessEvent) async -> Void = { _ in },
        now: @escaping @Sendable () -> Date = { .now },
        requiresContextPack: Bool = true
    ) {
        self.store = store
        self.grantProvider = grantProvider
        self.log = log
        self.now = now
        self.requiresContextPack = requiresContextPack
    }

    public func grantResolution() async -> MCPGrantResolution {
        await grantProvider()
    }

    public func call(tool name: String, arguments: JSONValue) async -> MCPToolResult {
        guard let tool = MCPToolName(rawValue: name) else {
            return MCPToolResult(text: "Unknown tool: \(name)", isError: true)
        }

        let resolution = await grantProvider()
        guard case .active(let grant) = resolution else {
            await record(tool, resolution: resolution, denial: resolution.denialReason)
            return MCPToolResult(text: denialMessage(for: resolution), isError: true)
        }
        if tool.mutatesStore, !grant.accessMode.allowsWrites {
            await record(tool, grant: grant, denial: .readOnly)
            return MCPToolResult(
                text: "This client is read-only. Approve write access in Gancho Settings.",
                isError: true)
        }

        do {
            switch tool {
            case .searchClips:
                return try await searchClips(
                    arguments.decoded(as: SearchClipsArgs.self), grant: grant)
            case .getClip:
                return try await getClip(arguments.decoded(as: GetClipArgs.self), grant: grant)
            case .createPin:
                return try await createPin(
                    arguments.decoded(as: CreatePinArgs.self), grant: grant)
            case .pasteStack:
                return try await pasteStack(
                    arguments.decoded(as: PasteStackArgs.self), grant: grant)
            case .listBoards:
                return try await listBoards(grant: grant)
            }
        } catch is DecodingError {
            await record(tool, grant: grant, denial: .invalidArguments)
            return MCPToolResult(
                text: "Invalid arguments for \(name). Check the tool's input schema.",
                isError: true)
        } catch {
            // Storage errors can carry paths or database details. Keep the
            // wire result and the ledger deliberately content-free.
            await record(tool, grant: grant, denial: .toolFailure)
            return MCPToolResult(text: "\(name) failed.", isError: true)
        }
    }

    // MARK: - Tools

    private func searchClips(
        _ args: SearchClipsArgs,
        grant: MCPClientGrant
    ) async throws -> MCPToolResult {
        guard let pack = grant.contextPack, pack.isExplicit else {
            if !requiresContextPack {
                var query = ClipSearchQuery(
                    text: args.query,
                    mode: Self.mode(args.mode),
                    markedOnly: grant.scope == .boards,
                    excludesSensitive: true)
                query.markedOnly = grant.scope == .boards
                var hits = try await store.search(query, limit: min(max(args.limit ?? 25, 1), 100))
                hits.removeAll(where: { $0.isSensitive })
                let summaries = hits.map(ClipSummary.init)
                await record(.searchClips, grant: grant, count: summaries.count)
                return ok(
                    SearchResult(
                        clips: summaries, count: summaries.count, scope: grant.scope.rawValue))
            }
            await record(.searchClips, grant: grant, denial: .outsideContext)
            return MCPToolResult(text: "This client has no approved context pack.", isError: true)
        }

        let limit = min(max(args.limit ?? 25, 1), 100)
        let currentTime = now()
        var query = ClipSearchQuery(
            text: args.query,
            mode: Self.mode(args.mode),
            dateRange: pack.timeScope.lowerBound(relativeTo: currentTime).map { $0...currentTime },
            boardID: pack.boardID,
            markedOnly: grant.scope == .boards,
            includedIDs: pack.clipIDs.isEmpty ? nil : pack.clipIDs,
            excludesSensitive: true)
        // A selected board is already stronger than broad "marked" scope and
        // avoids an unnecessary second condition on the same junction table.
        if pack.boardID != nil { query.markedOnly = false }

        var hits = try await store.search(query, limit: limit)
        hits.removeAll { item in
            item.isSensitive || (!pack.clipIDs.isEmpty && !pack.clipIDs.contains(item.id))
        }

        let summaries = hits.map(ClipSummary.init)
        await record(.searchClips, grant: grant, count: summaries.count)
        return ok(
            SearchResult(clips: summaries, count: summaries.count, scope: grant.scope.rawValue))
    }

    private func getClip(_ args: GetClipArgs, grant: MCPClientGrant) async throws -> MCPToolResult {
        guard let id = UUID(uuidString: args.id), let item = try await store.item(id: id) else {
            await record(.getClip, grant: grant)
            return MCPToolResult(text: "No clip with that id.", isError: true)
        }
        guard try await isInsideContext(item, grant: grant) else {
            // Same message as a genuine miss so a scoped client can't use the
            // reply to tell "exists but outside my context" from "doesn't exist"
            // — that would leak clip existence across the whole history. The
            // ledger still records the real .outsideContext reason.
            await record(.getClip, grant: grant, denial: .outsideContext)
            return MCPToolResult(text: "No clip with that id.", isError: true)
        }
        if item.isSensitive {
            await record(.getClip, grant: grant, denial: .sensitive)
            return MCPToolResult(
                text: "Clip is sensitive and cannot be read over MCP.", isError: true)
        }

        let summary = ClipSummary(item: item)
        if grant.scope == .metadata {
            await record(.getClip, grant: grant, denial: .scope)
            return ok(ClipDetail(summary: summary, content: nil, contentWithheld: true))
        }
        if grant.scope == .boards, !(try await isMarked(item)) {
            await record(.getClip, grant: grant, denial: .scope)
            return ok(ClipDetail(summary: summary, content: nil, contentWithheld: true))
        }
        let body = try await contentText(for: id)
        await record(.getClip, grant: grant, count: 1)
        return ok(ClipDetail(summary: summary, content: body, contentWithheld: false))
    }

    private func createPin(
        _ args: CreatePinArgs,
        grant: MCPClientGrant
    ) async throws -> MCPToolResult {
        guard let id = UUID(uuidString: args.id), let item = try await store.item(id: id) else {
            await record(.createPin, grant: grant)
            return MCPToolResult(text: "No clip with that id.", isError: true)
        }
        guard try await isInsideContext(item, grant: grant) else {
            // Generic miss message — see getClip: don't let the reply reveal
            // that an out-of-context id exists elsewhere in the store.
            await record(.createPin, grant: grant, denial: .outsideContext)
            return MCPToolResult(text: "No clip with that id.", isError: true)
        }
        if item.isSensitive {
            await record(.createPin, grant: grant, denial: .sensitive)
            return MCPToolResult(text: "Sensitive clips cannot be pinned over MCP.", isError: true)
        }

        if !requiresContextPack {
            var boardName: String?
            if let requested = args.board?.trimmingCharacters(in: .whitespacesAndNewlines),
                !requested.isEmpty
            {
                let board = try await board(named: requested)
                try await store.assign(clipID: id, toBoard: board.id)
                boardName = board.name
            }
            try await store.setPinned(id: id, true)
            await record(.createPin, grant: grant)
            return ok(CreatePinResult(id: args.id, pinned: true, board: boardName))
        }

        // A client grant approves organization inside a fixed context, not
        // arbitrary board creation. A requested board must be the selected
        // context board; curated packs may only pin.
        let requestedBoard = args.board?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let requestedBoard, !requestedBoard.isEmpty {
            guard let selectedName = grant.contextPack?.boardName,
                requestedBoard.caseInsensitiveCompare(selectedName) == .orderedSame
            else {
                await record(.createPin, grant: grant, denial: .outsideContext)
                return MCPToolResult(
                    text: "This client cannot organize outside its approved context pack.",
                    isError: true)
            }
        }

        try await store.setPinned(id: id, true)
        await record(.createPin, grant: grant)
        return ok(
            CreatePinResult(
                id: args.id, pinned: true, board: grant.contextPack?.boardName))
    }

    private func pasteStack(
        _ args: PasteStackArgs,
        grant: MCPClientGrant
    ) async throws -> MCPToolResult {
        guard args.ids.count <= Self.maximumPasteStackClips else {
            await record(.pasteStack, grant: grant, denial: .invalidArguments)
            return MCPToolResult(
                text: "paste_stack accepts at most \(Self.maximumPasteStackClips) clip ids.",
                isError: true)
        }
        if grant.scope == .metadata {
            await record(.pasteStack, grant: grant, denial: .scope)
            return MCPToolResult(
                text: "paste_stack needs content access approved in Gancho Settings.",
                isError: true)
        }
        var clips: [StackClip] = []
        for raw in args.ids {
            guard let id = UUID(uuidString: raw), let item = try await store.item(id: id) else {
                continue
            }
            // Context before the sensitive veto — same order as getClip/createPin
            // so out-of-context and sensitive are never distinguishable if a
            // future change ever surfaces a per-item reason here.
            if !(try await isInsideContext(item, grant: grant)) { continue }
            if item.isSensitive { continue }
            if grant.scope == .boards, !(try await isMarked(item)) { continue }
            guard let body = try await contentText(for: id) else { continue }
            clips.append(StackClip(id: raw, title: item.title, text: body))
        }
        await record(.pasteStack, grant: grant, count: clips.count)
        return ok(
            PasteStackResult(
                clips: clips, combinedText: clips.map(\.text).joined(separator: "\n\n"),
                count: clips.count))
    }

    private func listBoards(grant: MCPClientGrant) async throws -> MCPToolResult {
        let allBoards = try await store.pinboards()
        let boards: [Pinboard]
        if let selectedID = grant.contextPack?.boardID {
            boards = allBoards.filter { $0.id == selectedID }
        } else if !requiresContextPack {
            boards = allBoards
        } else {
            // A curated clip set does not authorize ambient board metadata.
            boards = []
        }
        await record(.listBoards, grant: grant, count: boards.count)
        return ok(ListBoardsResult(boards: boards.map(BoardSummary.init), count: boards.count))
    }

    // MARK: - Context and exposure

    private func isInsideContext(
        _ item: ClipItem,
        grant: MCPClientGrant
    ) async throws -> Bool {
        guard let pack = grant.contextPack, pack.isExplicit else { return !requiresContextPack }
        let boardIDs =
            pack.boardID == nil ? Set<UUID>() : try await store.boardIDs(for: item.id)
        return pack.contains(item: item, boardIDs: boardIDs, now: now())
    }

    private func isMarked(_ item: ClipItem) async throws -> Bool {
        if item.isPinned { return true }
        return !(try await store.boardIDs(for: item.id)).isEmpty
    }

    private func contentText(for id: UUID) async throws -> String? {
        switch try await store.content(for: id) {
        case .text(let text): return text
        case .fileReferences(let paths): return paths.joined(separator: "\n")
        case .binary(let data, let type):
            return "[binary content: \(type), \(ByteSize.formatted(data.count))]"
        case nil: return nil
        }
    }

    private func board(named name: String) async throws -> Pinboard {
        if let existing = try await store.pinboards().first(where: {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) {
            return existing
        }
        return try await store.createPinboard(name: name, sfSymbol: "square.stack")
    }

    // MARK: - Ledger

    private func record(
        _ tool: MCPToolName,
        grant: MCPClientGrant,
        count: Int = 0,
        denial: MCPAccessDenialReason? = nil
    ) async {
        await log(
            MCPAccessEvent(
                tool: tool,
                scope: grant.scope,
                accessMode: grant.accessMode,
                grantID: grant.id,
                clientName: grant.safeClientName,
                resultCount: count,
                wasDenied: denial != nil,
                denialReason: denial,
                occurredAt: now()))
    }

    private func record(
        _ tool: MCPToolName,
        resolution: MCPGrantResolution,
        denial: MCPAccessDenialReason?
    ) async {
        if let grant = resolution.grant {
            await record(tool, grant: grant, denial: denial)
        } else {
            await log(
                MCPAccessEvent(
                    tool: tool,
                    scope: .metadata,
                    wasDenied: true,
                    denialReason: denial,
                    occurredAt: now()))
        }
    }

    private func denialMessage(for resolution: MCPGrantResolution) -> String {
        switch resolution {
        case .active:
            "Access denied."
        case .disabled:
            "Gancho MCP access is off. Enable it in Gancho Settings."
        case .missing:
            "This MCP client has no approved grant. Create one in Gancho Settings."
        case .invalidContext:
            "This MCP client grant has no explicit context. Create a new grant in Gancho Settings."
        case .expired:
            "This MCP client grant expired. Renew it in Gancho Settings."
        case .revoked:
            "This MCP client grant was revoked. Create a new grant in Gancho Settings."
        }
    }

    private func ok(_ value: some Encodable) -> MCPToolResult {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let text =
            (try? encoder.encode(value)).flatMap { String(data: $0, encoding: .utf8) } ?? "{}"
        return MCPToolResult(text: text)
    }

    private static func mode(_ raw: String?) -> ClipSearchQuery.Mode {
        switch raw?.lowercased() {
        case "exact": return .exact
        case "regex": return .regex
        default: return .fuzzy
        }
    }

    static let maximumPasteStackClips = 100
}

import Foundation
import GanchoKit

/// Runs the four MCP tools against the store under a fixed access scope,
/// enforcing the privacy rules in ONE place:
///
/// - Sensitive clips (`isSensitive`) are NEVER exposed or mutated, in any
///   scope — the same veto the capture pipeline applies.
/// - `metadata` scope yields titles/previews but no content bodies; tools
///   that exist to return content are denied.
/// - `boards` scope restricts everything to clips the user marked (pinned).
/// - Every call is logged (tool + scope + count + denied flag, no content).
///
/// The runner is transport-agnostic: it takes decoded `JSONValue` arguments
/// and returns an `MCPToolResult`. The stdio server and the CLI share it.
public struct MCPToolRunner: Sendable {
    private let store: any MCPClipStore
    public let scope: MCPAccessScope
    private let log: @Sendable (MCPAccessEvent) async -> Void

    /// - Parameter log: sink for access events; the executable forwards these
    ///   to the GRDB access log the Privacy Center reads.
    public init(
        store: any MCPClipStore,
        scope: MCPAccessScope,
        log: @escaping @Sendable (MCPAccessEvent) async -> Void = { _ in }
    ) {
        self.store = store
        self.scope = scope
        self.log = log
    }

    /// Dispatches a `tools/call` by wire name. Unknown names and malformed
    /// arguments come back as `isError` results (not JSON-RPC errors) so the
    /// agent sees a readable message instead of a transport failure.
    public func call(tool name: String, arguments: JSONValue) async -> MCPToolResult {
        guard let tool = MCPToolName(rawValue: name) else {
            return MCPToolResult(text: "Unknown tool: \(name)", isError: true)
        }
        do {
            switch tool {
            case .searchClips:
                return try await searchClips(arguments.decoded(as: SearchClipsArgs.self))
            case .getClip:
                return try await getClip(arguments.decoded(as: GetClipArgs.self))
            case .createPin:
                return try await createPin(arguments.decoded(as: CreatePinArgs.self))
            case .pasteStack:
                return try await pasteStack(arguments.decoded(as: PasteStackArgs.self))
            }
        } catch is DecodingError {
            return MCPToolResult(
                text: "Invalid arguments for \(name). Check the tool's input schema.",
                isError: true)
        } catch {
            return MCPToolResult(text: "\(name) failed: \(error)", isError: true)
        }
    }

    // MARK: - Tools

    private func searchClips(_ args: SearchClipsArgs) async throws -> MCPToolResult {
        let limit = min(max(args.limit ?? 25, 1), 100)
        let query = ClipSearchQuery(text: args.query, mode: Self.mode(args.mode))
        var hits = try await store.search(query, limit: limit)
        hits.removeAll { $0.isSensitive }
        if scope == .boards { hits.removeAll { !$0.isPinned } }

        let summaries = hits.map(ClipSummary.init)
        await record(.searchClips, count: summaries.count)
        return ok(SearchResult(clips: summaries, count: summaries.count, scope: scope.rawValue))
    }

    private func getClip(_ args: GetClipArgs) async throws -> MCPToolResult {
        guard let id = UUID(uuidString: args.id), let item = try await store.item(id: id) else {
            await record(.getClip, count: 0)
            return MCPToolResult(text: "No clip with id \(args.id).", isError: true)
        }
        // Sensitive veto: refuse outright, even under `all`.
        if item.isSensitive {
            await record(.getClip, denied: true)
            return MCPToolResult(
                text: "Clip is sensitive and cannot be read over MCP.", isError: true)
        }
        // Scope gates on the CONTENT body; metadata is always describable.
        let summary = ClipSummary(item: item)
        if scope == .metadata {
            await record(.getClip, denied: true)
            return ok(ClipDetail(summary: summary, content: nil, contentWithheld: true))
        }
        if scope == .boards, !item.isPinned {
            await record(.getClip, denied: true)
            return ok(ClipDetail(summary: summary, content: nil, contentWithheld: true))
        }
        let body = try await contentText(for: id)
        await record(.getClip, count: 1)
        return ok(ClipDetail(summary: summary, content: body, contentWithheld: false))
    }

    private func createPin(_ args: CreatePinArgs) async throws -> MCPToolResult {
        guard let id = UUID(uuidString: args.id), let item = try await store.item(id: id) else {
            await record(.createPin, count: 0)
            return MCPToolResult(text: "No clip with id \(args.id).", isError: true)
        }
        if item.isSensitive {
            await record(.createPin, denied: true)
            return MCPToolResult(text: "Sensitive clips cannot be pinned over MCP.", isError: true)
        }

        var boardName: String?
        if let requested = args.board?.trimmingCharacters(in: .whitespacesAndNewlines),
            !requested.isEmpty
        {
            let board = try await board(named: requested)
            try await store.assign(clipID: id, toBoard: board.id)  // also pins
            boardName = board.name
        } else {
            try await store.setPinned(id: id, true)
        }
        await record(.createPin, count: 0)
        return ok(CreatePinResult(id: args.id, pinned: true, board: boardName))
    }

    private func pasteStack(_ args: PasteStackArgs) async throws -> MCPToolResult {
        // The whole point of a stack is its content; metadata scope can't serve it.
        if scope == .metadata {
            await record(.pasteStack, denied: true)
            return MCPToolResult(
                text: "paste_stack needs content access. Widen the MCP scope in Gancho Settings.",
                isError: true)
        }
        var clips: [StackClip] = []
        for raw in args.ids {
            guard let id = UUID(uuidString: raw), let item = try await store.item(id: id) else {
                continue
            }
            if item.isSensitive { continue }
            if scope == .boards, !item.isPinned { continue }
            guard let body = try await contentText(for: id) else { continue }
            clips.append(StackClip(id: raw, title: item.title, text: body))
        }
        await record(.pasteStack, count: clips.count)
        return ok(
            PasteStackResult(
                clips: clips, combinedText: clips.map(\.text).joined(separator: "\n\n"),
                count: clips.count))
    }

    // MARK: - Helpers

    /// Text view of a clip's content. Binary payloads are described, never
    /// dumped — an agent shouldn't receive megabytes of base64 unasked, and
    /// the bytes can carry more than the preview implies.
    private func contentText(for id: UUID) async throws -> String? {
        switch try await store.content(for: id) {
        case .text(let text): return text
        case .fileReferences(let paths): return paths.joined(separator: "\n")
        case .binary(let data, let type):
            return "[binary content: \(type), \(ByteSize.formatted(data.count))]"
        case nil: return nil
        }
    }

    /// Finds a board by name (case-insensitive) or creates it.
    private func board(named name: String) async throws -> Pinboard {
        if let existing = try await store.pinboards().first(where: {
            $0.name.caseInsensitiveCompare(name) == .orderedSame
        }) {
            return existing
        }
        return try await store.createPinboard(name: name)
    }

    private func record(_ tool: MCPToolName, count: Int = 0, denied: Bool = false) async {
        await log(MCPAccessEvent(tool: tool, scope: scope, resultCount: count, wasDenied: denied))
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
}

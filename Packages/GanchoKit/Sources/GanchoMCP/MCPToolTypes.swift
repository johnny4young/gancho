import Foundation
import GanchoKit

// MARK: - Tool arguments (decoded from `tools/call` `arguments`)

struct SearchClipsArgs: Decodable {
    let query: String
    let limit: Int?
    /// `exact` | `fuzzy` (default) | `regex`.
    let mode: String?
}

struct GetClipArgs: Decodable {
    let id: String
}

struct CreatePinArgs: Decodable {
    let id: String
    /// Optional board name. Live grants accept only their approved context
    /// board; static embedded policy may create the board when needed.
    let board: String?
}

struct PasteStackArgs: Decodable {
    let ids: [String]
}

// MARK: - Tool results (encoded into the text content block)

/// Clip metadata — the only shape returned by `search_clips`, and all that
/// `metadata` scope ever reveals. The preview is the same sanitized string
/// the app shows in lists.
struct ClipSummary: Encodable {
    let id: String
    let title: String
    let preview: String
    let kind: String
    let isPinned: Bool
    let createdAt: Date
    let sourceApp: String?

    init(item: ClipItem) {
        id = item.id.uuidString
        title = item.title
        preview = item.preview
        kind = item.kind.rawValue
        isPinned = item.isPinned
        createdAt = item.createdAt
        sourceApp = item.sourceAppBundleID
    }
}

struct SearchResult: Encodable {
    let clips: [ClipSummary]
    let count: Int
    let scope: String
}

struct ClipDetail: Encodable {
    let summary: ClipSummary
    /// The content body — nil when the scope withholds it.
    let content: String?
    /// True when metadata/boards scope refused the body; the agent still sees
    /// the summary and the reason.
    let contentWithheld: Bool
}

struct CreatePinResult: Encodable {
    let id: String
    let pinned: Bool
    let board: String?
}

struct StackClip: Encodable {
    let id: String
    let title: String
    let text: String
}

struct PasteStackResult: Encodable {
    let clips: [StackClip]
    let combinedText: String
    let count: Int
}

/// Board metadata — the only shape `list_boards` returns. Live grants expose
/// only their selected context board; curated clip sets expose no ambient
/// board list.
struct BoardSummary: Encodable {
    let id: String
    let name: String
    let sfSymbol: String

    init(board: Pinboard) {
        id = board.id.uuidString
        name = board.name
        sfSymbol = board.sfSymbol
    }
}

struct ListBoardsResult: Encodable {
    let boards: [BoardSummary]
    let count: Int
}

// MARK: - Tool catalog (advertised by `tools/list`)

extension MCPToolRunner {
    /// The five tools, with JSON Schemas for their arguments. Read-only grants
    /// omit `create_pin` at the protocol edge; scope governs returned content.
    public static let toolDescriptors: [MCPToolDescriptor] = [
        MCPToolDescriptor(
            name: MCPToolName.searchClips.rawValue,
            description:
                // swiftlint:disable:next line_length
                "Search the Gancho clipboard history. Returns clip metadata only (id, title, preview, kind, pinned state, capture time, source app) and never content; call get_clip for a clip's full content. Results stay inside the grant's approved context and never include clips marked sensitive. An unrecognized mode falls back to fuzzy.",
            inputSchema: schema(
                properties: [
                    "query": property("string", "Text to search for in clip titles and content."),
                    "limit": property(
                        "integer", "Max results, default 25; values outside 1–100 are clamped."),
                    "mode": property("string", "Match mode: exact, fuzzy (default), or regex.")
                ], required: ["query"])),
        MCPToolDescriptor(
            name: MCPToolName.getClip.rawValue,
            description:
                // swiftlint:disable:next line_length
                "Fetch one clip by id. Content is withheld (metadata still returned, contentWithheld = true) under the 'metadata' scope and, under the 'boards' scope, for clips not on an approved board. Sensitive clips return an error result instead of content.",
            inputSchema: schema(
                properties: ["id": property("string", "The clip id from search_clips.")],
                required: ["id"])),
        MCPToolDescriptor(
            name: MCPToolName.createPin.rawValue,
            description:
                // swiftlint:disable:next line_length
                "Pin a clip inside the client's approved context. Requires a read-write grant; a read-only grant is not offered this tool at all. A `board`, when given, must match the grant's own approved board name (case-insensitive) - a client can never pin into a board outside its context. Sensitive clips cannot be pinned.",
            inputSchema: schema(
                properties: [
                    "id": property("string", "The clip id to pin."),
                    "board": property("string", "Optional approved context-board name.")
                ], required: ["id"])),
        MCPToolDescriptor(
            name: MCPToolName.pasteStack.rawValue,
            description:
                // swiftlint:disable:next line_length
                "Assemble several clips, in order, into one block of text to paste. Requires content access (returns an error under the 'metadata' scope). Accepts at most 100 ids; ids that are unknown, sensitive, or unreadable under the grant are skipped silently, and `count` reports how many were included.",
            inputSchema: schema(
                properties: [
                    "ids": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "maxItems": .int(MCPToolRunner.maximumPasteStackClips),
                        "description": .string("Clip ids in paste order.")
                    ])
                ], required: ["ids"])),
        MCPToolDescriptor(
            name: MCPToolName.listBoards.rawValue,
            description:
                // swiftlint:disable:next line_length
                "List the pinboards clips can be organized onto. Returns board metadata only (id, name, sfSymbol), so it works under every scope.",
            inputSchema: schema(properties: [:], required: []))
    ]

    private static func schema(properties: [String: JSONValue], required: [String]) -> JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object(properties),
            "required": .array(required.map(JSONValue.string))
        ])
    }

    private static func property(_ type: String, _ description: String) -> JSONValue {
        .object(["type": .string(type), "description": .string(description)])
    }
}

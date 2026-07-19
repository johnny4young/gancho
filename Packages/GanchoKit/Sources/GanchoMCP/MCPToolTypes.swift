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
                "Search the Gancho clipboard history. Returns clip metadata (id, title, preview, kind). Use get_clip to read a clip's full content.",
            inputSchema: schema(
                properties: [
                    "query": property("string", "Text to search for in clip titles and content."),
                    "limit": property("integer", "Max results (1–100, default 25)."),
                    "mode": property("string", "Match mode: exact, fuzzy (default), or regex.")
                ], required: ["query"])),
        MCPToolDescriptor(
            name: MCPToolName.getClip.rawValue,
            description:
                // swiftlint:disable:next line_length
                "Fetch one clip's full content by id. Content is withheld under the 'metadata' scope and for sensitive clips.",
            inputSchema: schema(
                properties: ["id": property("string", "The clip id from search_clips.")],
                required: ["id"])),
        MCPToolDescriptor(
            name: MCPToolName.createPin.rawValue,
            description:
                // swiftlint:disable:next line_length
                "Pin a clip inside the client’s approved context. Requires an explicit read-write grant; arbitrary board creation is not allowed.",
            inputSchema: schema(
                properties: [
                    "id": property("string", "The clip id to pin."),
                    "board": property("string", "Optional approved context-board name.")
                ], required: ["id"])),
        MCPToolDescriptor(
            name: MCPToolName.pasteStack.rawValue,
            description:
                // swiftlint:disable:next line_length
                "Assemble several clips, in order, into one stack of text to paste. Needs content access (not available under 'metadata' scope).",
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

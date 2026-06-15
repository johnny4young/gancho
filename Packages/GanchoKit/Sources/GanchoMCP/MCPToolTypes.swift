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
    /// Optional board name; created if it doesn't exist. Without it the clip
    /// is pinned to plain history.
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

// MARK: - Tool catalog (advertised by `tools/list`)

extension MCPToolRunner {
    /// The four tools, with JSON Schemas for their arguments. Static metadata
    /// — independent of scope; the scope governs what each call returns.
    public static let toolDescriptors: [MCPToolDescriptor] = [
        MCPToolDescriptor(
            name: MCPToolName.searchClips.rawValue,
            description:
                "Search the Gancho clipboard history. Returns clip metadata (id, title, preview, kind). Use get_clip to read a clip's full content.",
            inputSchema: schema(
                properties: [
                    "query": property("string", "Text to search for in clip titles and content."),
                    "limit": property("integer", "Max results (1–100, default 25)."),
                    "mode": property("string", "Match mode: exact, fuzzy (default), or regex."),
                ], required: ["query"])),
        MCPToolDescriptor(
            name: MCPToolName.getClip.rawValue,
            description:
                "Fetch one clip's full content by id. Content is withheld under the 'metadata' scope and for sensitive clips.",
            inputSchema: schema(
                properties: ["id": property("string", "The clip id from search_clips.")],
                required: ["id"])),
        MCPToolDescriptor(
            name: MCPToolName.createPin.rawValue,
            description:
                "Pin a clip so it survives history retention. Optionally place it on a named board (created if missing).",
            inputSchema: schema(
                properties: [
                    "id": property("string", "The clip id to pin."),
                    "board": property("string", "Optional board name to add the clip to."),
                ], required: ["id"])),
        MCPToolDescriptor(
            name: MCPToolName.pasteStack.rawValue,
            description:
                "Assemble several clips, in order, into one stack of text to paste. Needs content access (not available under 'metadata' scope).",
            inputSchema: schema(
                properties: [
                    "ids": .object([
                        "type": .string("array"),
                        "items": .object(["type": .string("string")]),
                        "description": .string("Clip ids in paste order."),
                    ])
                ], required: ["ids"])),
    ]

    private static func schema(properties: [String: JSONValue], required: [String]) -> JSONValue {
        .object([
            "type": .string("object"),
            "properties": .object(properties),
            "required": .array(required.map(JSONValue.string)),
        ])
    }

    private static func property(_ type: String, _ description: String) -> JSONValue {
        .object(["type": .string(type), "description": .string(description)])
    }
}

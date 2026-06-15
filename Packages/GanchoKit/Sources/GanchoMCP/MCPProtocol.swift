import Foundation

/// JSON-RPC 2.0 request. `id` is absent for notifications (no reply expected);
/// `params` is tool- and method-specific, kept as raw `JSONValue`.
public struct JSONRPCRequest: Decodable, Sendable {
    public let jsonrpc: String
    public let id: JSONValue?
    public let method: String
    public let params: JSONValue?

    public init(jsonrpc: String = "2.0", id: JSONValue?, method: String, params: JSONValue?) {
        self.jsonrpc = jsonrpc
        self.id = id
        self.method = method
        self.params = params
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jsonrpc = (try? container.decode(String.self, forKey: .jsonrpc)) ?? "2.0"
        id = try container.decodeIfPresent(JSONValue.self, forKey: .id)
        method = try container.decode(String.self, forKey: .method)
        params = try container.decodeIfPresent(JSONValue.self, forKey: .params)
    }

    private enum CodingKeys: String, CodingKey { case jsonrpc, id, method, params }

    /// A notification carries no `id` and gets no response (per JSON-RPC 2.0).
    public var isNotification: Bool { id == nil }
}

/// JSON-RPC 2.0 error object. Codes follow the spec's reserved range; tool
/// failures use the application range and never carry clip content in `data`.
public struct JSONRPCError: Codable, Equatable, Sendable, Error {
    public let code: Int
    public let message: String
    public let data: JSONValue?

    public init(code: Int, message: String, data: JSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }

    public static let parseFailure = JSONRPCError(code: -32700, message: "Parse error")
    public static let invalidRequest = JSONRPCError(code: -32600, message: "Invalid request")
    public static func methodNotFound(_ method: String) -> JSONRPCError {
        JSONRPCError(code: -32601, message: "Method not found: \(method)")
    }
    public static func invalidParams(_ detail: String) -> JSONRPCError {
        JSONRPCError(code: -32602, message: "Invalid params: \(detail)")
    }
    public static func internalError(_ detail: String) -> JSONRPCError {
        JSONRPCError(code: -32603, message: "Internal error: \(detail)")
    }
}

/// JSON-RPC 2.0 response. Encodes `jsonrpc` plus exactly one of `result` /
/// `error`; a parse failure with no recoverable id replies with `null`.
public struct JSONRPCResponse: Encodable, Sendable {
    public let id: JSONValue
    public let result: JSONValue?
    public let error: JSONRPCError?

    public init(id: JSONValue, result: JSONValue) {
        self.id = id
        self.result = result
        self.error = nil
    }

    public init(id: JSONValue, error: JSONRPCError) {
        self.id = id
        self.result = nil
        self.error = error
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("2.0", forKey: .jsonrpc)
        try container.encode(id, forKey: .id)
        if let error {
            try container.encode(error, forKey: .error)
        } else {
            try container.encode(result ?? .null, forKey: .result)
        }
    }

    private enum CodingKeys: String, CodingKey { case jsonrpc, id, result, error }
}

/// A tool as advertised by `tools/list`: name, one-line description, and a
/// JSON Schema for its arguments.
public struct MCPToolDescriptor: Encodable, Sendable {
    public let name: String
    public let description: String
    public let inputSchema: JSONValue

    public init(name: String, description: String, inputSchema: JSONValue) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

/// The payload `tools/call` returns: text content blocks plus an error flag.
/// Gancho returns a single JSON text block the agent parses.
public struct MCPToolResult: Encodable, Sendable {
    public struct TextContent: Encodable, Sendable {
        public let type = "text"
        public let text: String
    }

    public let content: [TextContent]
    public let isError: Bool

    public init(text: String, isError: Bool = false) {
        self.content = [TextContent(text: text)]
        self.isError = isError
    }
}

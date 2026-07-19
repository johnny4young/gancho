import Foundation
import GanchoKit

/// JSON-RPC 2.0 dispatcher implementing the slice of MCP a clipboard server
/// needs: `initialize`, `tools/list`, `tools/call`, and `ping`. Transport is
/// someone else's job — feed it decoded requests, get responses (or `nil` for
/// notifications) back. That keeps the whole protocol layer unit-testable
/// without a pipe.
///
/// When the feature is OFF (`isEnabled == false`) the server still completes
/// the handshake so a client can connect, but advertises zero tools and
/// refuses every `tools/call` — opt-in, enforced at the protocol edge.
public struct MCPServer: Sendable {
    /// Fallback MCP revision when the client doesn't state one; we echo the
    /// client's requested version when it does, for maximum compatibility.
    public static let defaultProtocolVersion = "2025-06-18"

    private let runner: MCPToolRunner
    private let isEnabled: Bool
    private let serverVersion: String

    public init(runner: MCPToolRunner, isEnabled: Bool, serverVersion: String = "0.1.0") {
        self.runner = runner
        self.isEnabled = isEnabled
        self.serverVersion = serverVersion
    }

    /// Handles one request. Returns `nil` for notifications (no reply per
    /// JSON-RPC 2.0).
    public func handle(_ request: JSONRPCRequest) async -> JSONRPCResponse? {
        if request.isNotification { return nil }
        let id = request.id ?? .null

        switch request.method {
        case "initialize":
            return JSONRPCResponse(
                id: id, result: await initializeResult(params: request.params))
        case "ping":
            return JSONRPCResponse(id: id, result: .object([:]))
        case "tools/list":
            return JSONRPCResponse(id: id, result: await toolsListResult())
        case "tools/call":
            return await toolsCallResult(id: id, params: request.params)
        default:
            return JSONRPCResponse(id: id, error: .methodNotFound(request.method))
        }
    }

    // MARK: - Methods

    private func initializeResult(params: JSONValue?) async -> JSONValue {
        let version = params?["protocolVersion"]?.stringValue ?? Self.defaultProtocolVersion
        let resolution = await runner.grantResolution()
        let instructions: String
        if !isEnabled {
            instructions = "Gancho MCP access is currently off. Enable it in Gancho Settings."
        } else {
            instructions =
                switch resolution {
                case .active(let grant):
                    "Gancho client \(grant.safeClientName) is approved with \(grant.scope.rawValue) scope and \(grant.accessMode.rawValue) access."
                case .disabled:
                    "Gancho MCP access is currently off. Enable it in Gancho Settings."
                case .missing:
                    "This MCP process has no approved client grant. Create one in Gancho Settings."
                case .invalidContext:
                    "This MCP client grant has no explicit context. Create a new grant in Gancho Settings."
                case .expired:
                    "This MCP client grant expired. Renew it in Gancho Settings."
                case .revoked:
                    "This MCP client grant was revoked. Create a new grant in Gancho Settings."
                }
        }
        return .object([
            "protocolVersion": .string(version),
            "capabilities": .object(["tools": .object([:])]),
            "serverInfo": .object([
                "name": .string("gancho"),
                "version": .string(serverVersion)
            ]),
            "instructions": .string(instructions)
        ])
    }

    private func toolsListResult() async -> JSONValue {
        let resolution = await runner.grantResolution()
        let tools: [MCPToolDescriptor]
        if isEnabled, case .active(let grant) = resolution {
            tools = MCPToolRunner.toolDescriptors.filter { descriptor in
                grant.accessMode.allowsWrites
                    || descriptor.name != MCPToolName.createPin.rawValue
            }
        } else {
            tools = []
        }
        return (try? JSONValue(encoding: ToolsList(tools: tools))) ?? .object(["tools": .array([])])
    }

    private func toolsCallResult(id: JSONValue, params: JSONValue?) async -> JSONRPCResponse {
        guard let name = params?["name"]?.stringValue else {
            return JSONRPCResponse(id: id, error: .invalidParams("missing tool name"))
        }
        guard isEnabled else {
            let denied = MCPToolResult(
                text: "Gancho MCP access is OFF. Enable it in Gancho → Settings.", isError: true)
            return JSONRPCResponse(id: id, result: encode(denied))
        }
        let arguments = params?["arguments"] ?? .object([:])
        let result = await runner.call(tool: name, arguments: arguments)
        return JSONRPCResponse(id: id, result: encode(result))
    }

    private func encode(_ result: MCPToolResult) -> JSONValue {
        (try? JSONValue(encoding: result))
            ?? .object(["content": .array([]), "isError": .bool(true)])
    }

    private struct ToolsList: Encodable {
        let tools: [MCPToolDescriptor]
    }
}

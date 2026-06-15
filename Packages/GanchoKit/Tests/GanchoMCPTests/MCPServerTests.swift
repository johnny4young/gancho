import Foundation
import GanchoKit
import Testing

@testable import GanchoMCP

@Suite("MCP server — handshake, tools/list, tools/call, opt-in gate")
struct MCPServerTests {
    private func server(enabled: Bool) async throws -> MCPServer {
        let store = try MCPTestStore.make()
        try await store.seedFixtures()
        let runner = MCPToolRunner(store: store, scope: .all)
        return MCPServer(runner: runner, isEnabled: enabled)
    }

    @Test("initialize echoes the client protocol version and identifies the server")
    func initialize() async throws {
        let server = try await server(enabled: true)
        let response = await server.handle(
            JSONRPCRequest(
                id: .int(1), method: "initialize",
                params: .object(["protocolVersion": .string("2025-03-26")])))
        #expect(response?.result?["protocolVersion"]?.stringValue == "2025-03-26")
        #expect(response?.result?["serverInfo"]?["name"]?.stringValue == "gancho")
    }

    @Test("notifications get no response")
    func notification() async throws {
        let server = try await server(enabled: true)
        let response = await server.handle(
            JSONRPCRequest(id: nil, method: "notifications/initialized", params: nil))
        #expect(response == nil)
    }

    @Test("ping replies with an empty object")
    func ping() async throws {
        let server = try await server(enabled: true)
        let response = await server.handle(JSONRPCRequest(id: .int(2), method: "ping", params: nil))
        #expect(response?.result == .object([:]))
    }

    @Test("unknown method is method-not-found")
    func unknownMethod() async throws {
        let server = try await server(enabled: true)
        let response = await server.handle(
            JSONRPCRequest(id: .int(3), method: "frobnicate", params: nil))
        #expect(response?.error?.code == -32601)
    }

    @Test("enabled server advertises all four tools")
    func toolsListEnabled() async throws {
        let server = try await server(enabled: true)
        let response = await server.handle(
            JSONRPCRequest(id: .int(4), method: "tools/list", params: nil))
        #expect(response?.result?["tools"]?.arrayValue?.count == 4)
    }

    @Test("tools/call routes to the runner and returns content")
    func toolsCall() async throws {
        let server = try await server(enabled: true)
        let response = await server.handle(
            JSONRPCRequest(
                id: .int(5), method: "tools/call",
                params: .object([
                    "name": .string("search_clips"),
                    "arguments": .object(["query": .string("alpha")]),
                ])))
        #expect(response?.result?["isError"]?.boolValue == false)
        let text = response?.result?["content"]?.arrayValue?.first?["text"]?.stringValue ?? "{}"
        let parsed = try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
        #expect(parsed["count"]?.intValue == 2)
    }

    // MARK: - Opt-in gate

    @Test("disabled server advertises zero tools")
    func toolsListDisabled() async throws {
        let server = try await server(enabled: false)
        let response = await server.handle(
            JSONRPCRequest(id: .int(1), method: "tools/list", params: nil))
        #expect(response?.result?["tools"]?.arrayValue?.count == 0)
    }

    @Test("disabled server refuses tools/call")
    func toolsCallDisabled() async throws {
        let server = try await server(enabled: false)
        let response = await server.handle(
            JSONRPCRequest(
                id: .int(2), method: "tools/call",
                params: .object([
                    "name": .string("search_clips"),
                    "arguments": .object(["query": .string("alpha")]),
                ])))
        #expect(response?.result?["isError"]?.boolValue == true)
    }

    // MARK: - stdio framing

    @Test("stdio transport parses a line and flags malformed JSON")
    func stdioLines() async throws {
        let server = try await server(enabled: true)
        let transport = MCPStdioTransport(server: server)
        let ok = await transport.response(forLine: #"{"jsonrpc":"2.0","id":1,"method":"ping"}"#)
        #expect(ok?.result == .object([:]))
        let bad = await transport.response(forLine: "this is not json")
        #expect(bad?.error?.code == -32700)
    }
}

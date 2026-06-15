import Foundation

/// Newline-delimited JSON-RPC over stdio — the transport MCP clients (Claude
/// Desktop, Cursor) spawn and talk to. One JSON message per line; responses
/// go to stdout, diagnostics must stay on stderr so they never corrupt the
/// stream. The protocol logic lives in `MCPServer`; this only moves bytes.
public struct MCPStdioTransport: Sendable {
    private let server: MCPServer

    public init(server: MCPServer) {
        self.server = server
    }

    /// Pumps requests until stdin reaches EOF (the client disconnected).
    public func run(
        input: FileHandle = .standardInput, output: FileHandle = .standardOutput
    ) async {
        do {
            for try await line in input.bytes.lines {
                guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
                if let response = await response(forLine: line) {
                    write(response, to: output)
                }
            }
        } catch {
            // A read error ends the session like EOF; nothing to recover.
        }
    }

    /// Decodes one line and dispatches it. A malformed line yields a parse
    /// error with a null id (we have no id to echo).
    func response(forLine line: String) async -> JSONRPCResponse? {
        guard let request = try? JSONDecoder().decode(JSONRPCRequest.self, from: Data(line.utf8))
        else {
            return JSONRPCResponse(id: .null, error: .parseFailure)
        }
        return await server.handle(request)
    }

    private func write(_ response: JSONRPCResponse, to output: FileHandle) {
        // Compact (no pretty-printing): the message MUST be a single line.
        guard var data = try? JSONEncoder().encode(response) else { return }
        data.append(0x0A)  // \n delimiter
        try? output.write(contentsOf: data)
    }
}

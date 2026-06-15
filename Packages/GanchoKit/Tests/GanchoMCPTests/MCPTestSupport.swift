import Foundation
import GanchoKit

@testable import GanchoMCP

/// A fresh GRDB store in a throwaway directory — exercises the real schema
/// (including the v9 access-log migration) and FTS search, so the tools are
/// tested against production storage, not a stub.
enum MCPTestStore {
    static func make() throws -> GRDBClipboardStore {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("gancho-mcp-tests-\(UUID().uuidString)", isDirectory: true)
        return try GRDBClipboardStore(directory: directory)
    }
}

/// Stable ids for the seeded fixtures so tests can address specific clips.
enum Fixture {
    static let plain = UUID()  // "alpha apple", not pinned, not sensitive
    static let pinned = UUID()  // "alpha pinned", pinned
    static let secret = UUID()  // sensitive
}

extension GRDBClipboardStore {
    /// Seeds three clips covering the axes the scope/veto rules turn on:
    /// a plain history clip, a pinned (marked) clip, and a sensitive one.
    func seedFixtures() async throws {
        try await insert(
            ClipItem(
                id: Fixture.plain, kind: .text, title: "Alpha apple",
                preview: "alpha apple", contentHash: ClipItem.hash(of: "apple", kind: .text)),
            content: .text("alpha apple body"))
        try await insert(
            ClipItem(
                id: Fixture.pinned, kind: .text, title: "Alpha pinned",
                preview: "alpha pinned", contentHash: ClipItem.hash(of: "pinned", kind: .text),
                isPinned: true),
            content: .text("alpha pinned body"))
        try await insert(
            ClipItem(
                id: Fixture.secret, kind: .text, title: "Secret token",
                preview: "alpha masked", contentHash: ClipItem.hash(of: "secret", kind: .text),
                isSensitive: true),
            content: .text("alpha AKIA-secret-value"))
    }
}

/// Collects access events so tests can assert what the runner logged. Build
/// the runner's log closure inline as `{ await sink.record($0) }`.
actor EventSink {
    private(set) var events: [MCPAccessEvent] = []
    func record(_ event: MCPAccessEvent) { events.append(event) }
}

/// Parses a tool result's single text block into a `JSONValue` for assertions
/// (the result DTOs are encode-only on the wire).
func resultJSON(_ result: MCPToolResult) throws -> JSONValue {
    let text = result.content.first?.text ?? "{}"
    return try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

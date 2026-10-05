import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("MCP policy and payload share a database snapshot")
struct MCPConsistentReadTests {
    @Test func aCommittedEditCannotReplaceTheAuthorizedSnapshotsBody() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("mcp-snapshot-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let gate = PayloadReadGate()
        var configuration = Configuration()
        configuration.prepareDatabase { db in db.trace { gate.observe("\($0)") } }
        let pool = try DatabasePool(
            path: directory.appendingPathComponent("store.sqlite").path,
            configuration: configuration)
        let store = GRDBClipboardStore(
            writer: pool, blobs: BlobStore(directory: directory.appendingPathComponent("blobs")))
        try store.migrate()
        let item = ClipItem(
            updatedAt: Date.now.addingTimeInterval(-60), preview: "approved body",
            contentHash: "approved-hash")
        try await store.insert(item, content: .text("approved body"))
        let grant = MCPClientGrant(
            clientName: "Snapshot fixture", scope: .all,
            contextPack: MCPContextPack(
                name: "Reviewed", clipIDs: [item.id],
                clipRevisions: [item.id.uuidString: item.contextRevision]))

        gate.arm()
        let read = Task {
            try await store.readForMCP(
                id: item.id, grant: grant, requiresContextPack: true, now: .now)
        }
        defer { gate.resume() }
        try #require(gate.waitForPayload(), "the authorized payload query must reach the gate")
        // The reader has already checked policy, but has not executed its payload
        // SELECT. A different WAL connection commits the replacement right now.
        try await store.updateClipText(id: item.id, text: "unapproved replacement")
        gate.resume()
        let result = try await read.value

        guard case .content(let captured, let content) = result else {
            Issue.record("the snapshot must retain the approved generation")
            return
        }
        #expect(captured.contextRevision == item.contextRevision)
        #expect(content == .text("approved body"))
        #expect(try await store.content(for: item.id) == .text("unapproved replacement"))
        #expect(
            try await store.readForMCP(
                id: item.id, grant: grant, requiresContextPack: true, now: .now) == .outsideContext)
    }
}

/// A test-only SQL trace gate: it pauses the real payload query after the earlier
/// metadata SELECT established the transaction snapshot. No production hook or sleep.
private final class PayloadReadGate: @unchecked Sendable {
    private let lock = NSLock()
    private var armed = false
    private let reached = DispatchSemaphore(value: 0)
    private let proceed = DispatchSemaphore(value: 0)

    func arm() {
        lock.lock()
        armed = true
        lock.unlock()
    }

    func observe(_ sql: String) {
        lock.lock()
        let shouldPause = armed && sql.hasPrefix(#"SELECT * FROM "clip""#)
        if shouldPause { armed = false }
        lock.unlock()
        guard shouldPause else { return }
        reached.signal()
        _ = proceed.wait(timeout: .now() + 30)
    }

    func waitForPayload() -> Bool { reached.wait(timeout: .now() + 30) == .success }
    func resume() { proceed.signal() }
}

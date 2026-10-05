import Foundation
import GanchoKit
import Testing

@testable import GanchoMCP

@Suite("MCP reviewed reads — intervening edits")
struct MCPReadRaceTests {
    @Test func legacySplitReadControlReturnsUnreviewedBytes() async throws {
        let (store, item, grant) = try await fixture()
        let metadata = try #require(try await store.items(ids: [item.id]).first)
        #expect(grant.contextPack?.contains(item: metadata, boardIDs: [], now: .now) == true)
        // This is the old tool's split-read sequence, using the real store. The
        // checked revision is still approved while the next read returns new bytes.
        let body = try await store.content(for: item.id)
        #expect(body == .text("unapproved replacement"))
        #expect(metadata.contextRevision == item.contextRevision)
    }

    @Test(arguments: ["get_clip", "paste_stack"])
    func toolReadsRejectAnEditBeforeTheSnapshot(tool: String) async throws {
        let (store, item, grant) = try await fixture()
        let sink = EventSink()
        let runner = MCPToolRunner(
            store: store, grantProvider: { .active(grant) }, log: { await sink.record($0) })
        let arguments: JSONValue =
            tool == "get_clip"
            ? .object(["id": .string(item.id.uuidString)])
            : .object(["ids": .array([.string(item.id.uuidString)])])

        let response = await runner.call(tool: tool, arguments: arguments)

        #expect(!response.content.contains { $0.text.contains("unapproved replacement") })
        if tool == "get_clip" {
            #expect(response.isError)
            #expect(await sink.events.last?.denialReason == .outsideContext)
        } else {
            #expect(!response.isError)
            #expect(try resultJSON(response)["count"]?.intValue == 0)
        }
        #expect(await sink.events.last?.resultCount == 0)
        #expect(try await store.base.content(for: item.id) == .text("unapproved replacement"))
    }

    private func fixture() async throws -> (EditingReadStore, ClipItem, MCPClientGrant) {
        let base = try MCPTestStore.make()
        let item = ClipItem(
            updatedAt: Date.now.addingTimeInterval(-60), preview: "approved body",
            contentHash: "approved-race-fixture")
        try await base.insert(item, content: .text("approved body"))
        let grant = MCPClientGrant(
            clientName: "Read-race fixture", scope: .all,
            contextPack: MCPContextPack(
                name: "Reviewed", clipIDs: [item.id],
                clipRevisions: [item.id.uuidString: item.contextRevision]))
        return (EditingReadStore(base: base), item, grant)
    }
}

/// Real-storage decorator that places the edit at the old content-read boundary
/// and at the new snapshot boundary, without touching any user database.
private struct EditingReadStore: MCPClipStore {
    let base: GRDBClipboardStore

    func readForMCP(
        id: UUID, grant: MCPClientGrant, requiresContextPack: Bool, now: Date
    ) async throws -> MCPClipReadResult {
        try await base.updateClipText(id: id, text: "unapproved replacement")
        return try await base.readForMCP(
            id: id, grant: grant, requiresContextPack: requiresContextPack, now: now)
    }

    func content(for id: UUID) async throws -> ClipContent? {
        try await base.updateClipText(id: id, text: "unapproved replacement")
        return try await base.content(for: id)
    }

    func search(_ query: ClipSearchQuery, limit: Int) async throws -> [ClipItem] {
        try await base.search(query, limit: limit)
    }
    func item(id: UUID) async throws -> ClipItem? { try await base.item(id: id) }
    func items(ids: [UUID]) async throws -> [ClipItem] { try await base.items(ids: ids) }
    func boardIDs(for id: UUID) async throws -> Set<UUID> { try await base.boardIDs(for: id) }
    func setPinned(id: UUID, _ pinned: Bool) async throws {
        try await base.setPinned(id: id, pinned)
    }
    func pinboards() async throws -> [Pinboard] { try await base.pinboards() }
    func createPinboard(name: String, sfSymbol: String) async throws -> Pinboard {
        try await base.createPinboard(name: name, sfSymbol: sfSymbol)
    }
    func assign(clipID: UUID, toBoard boardID: UUID) async throws {
        try await base.assign(clipID: clipID, toBoard: boardID)
    }
}

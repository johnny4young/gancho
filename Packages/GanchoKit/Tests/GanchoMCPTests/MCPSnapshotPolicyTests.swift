import Foundation
import GanchoKit
import Testing

@testable import GanchoMCP

@Suite("MCP snapshot policy — withheld payloads and pin checks")
struct MCPSnapshotPolicyTests {
    @Test("A payload that vanished after the snapshot is reported as withheld")
    func vanishedPayloadIsWithheld() async throws {
        let base = try MCPTestStore.make()
        try await base.seedFixtures()
        let store = PolicyOverrideStore(base: base, override: .vanishedPayload)
        let runner = MCPToolRunner(store: store, scope: .all) { _ in }

        let result = await runner.call(
            tool: "get_clip", arguments: .object(["id": .string(Fixture.plain.uuidString)]))

        #expect(!result.isError)
        let json = try resultJSON(result)
        #expect(json["contentWithheld"]?.boolValue == true)
        #expect(json["content"]?.stringValue == nil)
    }

    @Test("create_pin takes its sensitivity verdict from the snapshot read")
    func createPinUsesSnapshotVerdict() async throws {
        let base = try MCPTestStore.make()
        try await base.seedFixtures()
        // The plain fixture is not sensitive in the store; only the snapshot
        // read says otherwise. A split read would have pinned it.
        let store = PolicyOverrideStore(base: base, override: .sensitive)
        let sink = EventSink()
        let runner = MCPToolRunner(store: store, scope: .all, accessMode: .readWrite) {
            await sink.record($0)
        }

        let result = await runner.call(
            tool: "create_pin", arguments: .object(["id": .string(Fixture.plain.uuidString)]))

        #expect(result.isError)
        #expect(await sink.events.last?.denialReason == .sensitive)
        #expect(try await base.item(id: Fixture.plain)?.isPinned == false)
    }

    @Test("create_pin never asks the snapshot read for a payload")
    func createPinReadsMetadataOnly() async throws {
        let base = try MCPTestStore.make()
        try await base.seedFixtures()
        let store = PolicyOverrideStore(base: base, override: nil)
        let runner = MCPToolRunner(store: store, scope: .all, accessMode: .readWrite) { _ in }

        let result = await runner.call(
            tool: "create_pin", arguments: .object(["id": .string(Fixture.plain.uuidString)]))

        #expect(try resultJSON(result)["pinned"]?.boolValue == true)
        #expect(await store.recorder.scopes == [.metadata])
    }
}

private actor ScopeRecorder {
    private(set) var scopes: [MCPAccessScope] = []
    func record(_ scope: MCPAccessScope) { scopes.append(scope) }
}

/// Real-storage decorator whose snapshot read can be overridden, so the runner's
/// reaction to a given snapshot verdict is observable without a timing race.
private struct PolicyOverrideStore: MCPClipStore {
    enum Override: Sendable { case vanishedPayload, sensitive }

    let base: GRDBClipboardStore
    let override: Override?
    let recorder = ScopeRecorder()

    func readForMCP(
        id: UUID, grant: MCPClientGrant, requiresContextPack: Bool, now: Date
    ) async throws -> MCPClipReadResult {
        await recorder.record(grant.scope)
        let result = try await base.readForMCP(
            id: id, grant: grant, requiresContextPack: requiresContextPack, now: now)
        switch (override, result) {
        case (.vanishedPayload?, .content(let item, _)): return .content(item, nil)
        case (.sensitive?, _): return .sensitive
        default: return result
        }
    }

    func search(_ query: ClipSearchQuery, limit: Int) async throws -> [ClipItem] {
        try await base.search(query, limit: limit)
    }
    func item(id: UUID) async throws -> ClipItem? { try await base.item(id: id) }
    func items(ids: [UUID]) async throws -> [ClipItem] { try await base.items(ids: ids) }
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

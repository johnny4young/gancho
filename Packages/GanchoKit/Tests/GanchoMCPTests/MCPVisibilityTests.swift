import Foundation
import GanchoKit
import Testing

@testable import GanchoMCP

@Suite("MCP tool runner — expired, archived and metadata-only visibility")
struct MCPVisibilityTests {
    private func store() async throws -> GRDBClipboardStore {
        let store = try MCPTestStore.make()
        try await store.seedFixtures()
        return store
    }

    private func runner(
        _ store: GRDBClipboardStore, scope: MCPAccessScope = .all
    ) -> MCPToolRunner {
        MCPToolRunner(store: store, scope: scope, accessMode: .readWrite)
    }

    @Test("get_clip and paste_stack treat an expired clip as missing")
    func expiredClipIsMissing() async throws {
        let store = try await store()
        let expired = ClipItem(
            preview: "stale", contentHash: "expired-hash",
            expiresAt: Date.now.addingTimeInterval(-60))
        try await store.insert(expired, content: .text("stale body"))
        let runner = runner(store)

        let get = await runner.call(
            tool: "get_clip", arguments: .object(["id": .string(expired.id.uuidString)]))
        #expect(get.isError)

        let stack = await runner.call(
            tool: "paste_stack",
            arguments: .object(["ids": .array([.string(expired.id.uuidString)])]))
        #expect(try resultJSON(stack)["count"]?.intValue == 0)
    }

    @Test("get_clip and paste_stack treat an archived clip as missing")
    func archivedClipIsMissing() async throws {
        let store = try await store()
        let old = ClipItem(
            createdAt: Date.now.addingTimeInterval(-400 * 86_400), preview: "old",
            contentHash: "archived-hash")
        try await store.insert(old, content: .text("archived body"))
        try await TierEnforcement(store: store).enforce(tier: .free)
        #expect(try await store.archivedCount() == 1)
        let runner = runner(store)

        let get = await runner.call(
            tool: "get_clip", arguments: .object(["id": .string(old.id.uuidString)]))
        #expect(get.isError)

        let stack = await runner.call(
            tool: "paste_stack",
            arguments: .object(["ids": .array([.string(old.id.uuidString)])]))
        #expect(try resultJSON(stack)["count"]?.intValue == 0)
    }

    @Test("metadata scope search never matches the clip body")
    func metadataSearchSkipsBody() async throws {
        let runner = runner(try await store(), scope: .metadata)

        let bodyOnly = await runner.call(
            tool: "search_clips", arguments: .object(["query": .string("body")]))
        #expect(try resultJSON(bodyOnly)["count"]?.intValue == 0)

        let titled = await runner.call(
            tool: "search_clips", arguments: .object(["query": .string("apple")]))
        #expect(try resultJSON(titled)["count"]?.intValue == 1)
    }

    @Test("metadata scope rejects regex search")
    func metadataRejectsRegex() async throws {
        let runner = runner(try await store(), scope: .metadata)

        let result = await runner.call(
            tool: "search_clips",
            arguments: .object(["query": .string("bo.y"), "mode": .string("regex")]))

        #expect(result.isError)
    }
}

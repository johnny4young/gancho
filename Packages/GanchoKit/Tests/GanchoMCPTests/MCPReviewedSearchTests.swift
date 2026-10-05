import Foundation
import GanchoKit
import Testing

@testable import GanchoMCP

@Suite("MCP search — reviewed revision boundaries")
struct MCPReviewedSearchTests {
    @Test(arguments: [MCPAccessScope.all, .metadata])
    func changedClipCannotExposeItsNewPreviewOrConsumeTheLimit(scope: MCPAccessScope) async throws {
        let store = try MCPTestStore.make()
        let sink = EventSink()
        let reviewedAt = Date.now.addingTimeInterval(-60)
        let allowed = ClipItem(
            createdAt: reviewedAt.addingTimeInterval(-60), updatedAt: reviewedAt,
            preview: "reviewed unchanged", contentHash: "reviewed-unchanged")
        let changed = ClipItem(
            createdAt: reviewedAt, updatedAt: reviewedAt,
            preview: "reviewed original", contentHash: "reviewed-original")
        for item in [allowed, changed] {
            try await store.insert(item, content: .text(item.preview))
        }
        let grant = MCPClientGrant(
            clientName: "Selected client", scope: scope,
            contextPack: MCPContextPack(
                name: "Reviewed selection", clipIDs: [allowed.id, changed.id],
                clipRevisions: [
                    allowed.id.uuidString: allowed.contextRevision,
                    changed.id.uuidString: changed.contextRevision
                ]))
        let runner = MCPToolRunner(
            store: store, grantProvider: { .active(grant) }, log: { await sink.record($0) })
        try await store.updateClipText(id: changed.id, text: "reviewed unapproved replacement")

        let response = await runner.call(
            tool: "search_clips",
            arguments: .object(["query": .string("reviewed"), "limit": .int(1)]))
        let result = try resultJSON(response)

        #expect(!response.isError)
        #expect(result["clips"]?.arrayValue?.map { $0["id"]?.stringValue } == [allowed.id.uuidString])
        #expect(!response.content.contains { $0.text.contains("unapproved replacement") })
        #expect(await sink.events.last?.resultCount == 1)
    }

    @Test func anEmptyReviewedSelectionNeverFallsBackToAmbientSearch() async throws {
        let store = try MCPTestStore.make()
        let item = ClipItem(preview: "reviewed match", contentHash: "reviewed-empty")
        try await store.insert(item, content: .text(item.preview))
        for revisions in [[String: String](), [item.id.uuidString: "older-revision"]] {
            let grant = MCPClientGrant(
                clientName: "Selected client", scope: .all,
                contextPack: MCPContextPack(
                    name: "Reviewed selection", clipIDs: [item.id], clipRevisions: revisions))
            let runner = MCPToolRunner(store: store, grantProvider: { .active(grant) })
            let response = await runner.call(
                tool: "search_clips", arguments: .object(["query": .string("reviewed")]))

            #expect(!response.isError)
            #expect(try resultJSON(response)["count"]?.intValue == 0)
        }
    }

    @Test func revisionKeysCannotExpandTheSelectedIDs() async throws {
        let store = try MCPTestStore.make()
        let allowed = ClipItem(preview: "reviewed allowed", contentHash: "reviewed-allowed")
        let outside = ClipItem(preview: "reviewed outside", contentHash: "reviewed-outside")
        for item in [allowed, outside] {
            try await store.insert(item, content: .text(item.preview))
        }
        let grant = MCPClientGrant(
            clientName: "Selected client", scope: .all,
            contextPack: MCPContextPack(
                name: "Reviewed selection", clipIDs: [allowed.id],
                clipRevisions: [
                    allowed.id.uuidString: allowed.contextRevision,
                    outside.id.uuidString: outside.contextRevision
                ]))
        let runner = MCPToolRunner(store: store, grantProvider: { .active(grant) })
        let response = await runner.call(
            tool: "search_clips", arguments: .object(["query": .string("reviewed")]))

        #expect(
            try resultJSON(response)["clips"]?.arrayValue?.map { $0["id"]?.stringValue }
                == [allowed.id.uuidString])
    }
}

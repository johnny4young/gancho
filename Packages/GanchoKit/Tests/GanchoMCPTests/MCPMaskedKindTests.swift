import Foundation
import GanchoKit
import Testing

@testable import GanchoMCP

@Suite("MCP masked kinds — missing sensitivity flag")
struct MCPMaskedKindTests {
    @Test(
        "Every content tool vetoes intrinsically masked clips in either grant mode",
        arguments: [ClipContentKind.jwt, .creditCard, .secret], [false, true])
    func maskedKinds(kind: ClipContentKind, liveGrant: Bool) async throws {
        let store = try MCPTestStore.make()
        let sink = EventSink()
        let item = ClipItem(
            kind: kind, title: "Synthetic masked fixture", preview: "maskedfixture preview",
            contentHash: "maskedfixture-\(kind.rawValue)", isSensitive: false)
        try await store.insert(item, content: .text("maskedfixture body"))
        let grant = MCPClientGrant(
            clientName: "Synthetic test client", scope: .all, accessMode: .readWrite,
            contextPack: MCPContextPack(name: "Test selection", clipIDs: [item.id]))
        let runner =
            liveGrant
            ? MCPToolRunner(
                store: store, grantProvider: { .active(grant) },
                log: { await sink.record($0) })
            : MCPToolRunner(
                store: store, scope: .all, accessMode: .readWrite,
                log: { await sink.record($0) })

        let search = try resultJSON(
            await runner.call(
                tool: "search_clips", arguments: .object(["query": .string("maskedfixture")])))
        #expect(search["count"]?.intValue == 0)
        #expect(await sink.events.last?.resultCount == 0)

        for tool in ["get_clip", "create_pin"] {
            let result = await runner.call(
                tool: tool, arguments: .object(["id": .string(item.id.uuidString)]))
            #expect(result.isError == true)
            #expect(await sink.events.last?.denialReason == .sensitive)
        }
        #expect(try await store.item(id: item.id)?.isPinned == false)

        let stack = try resultJSON(
            await runner.call(
                tool: "paste_stack",
                arguments: .object(["ids": .array([.string(item.id.uuidString)])])))
        #expect(stack["count"]?.intValue == 0)
        #expect(stack["combinedText"]?.stringValue?.isEmpty == true)
        #expect(await sink.events.last?.resultCount == 0)
    }

    @Test(
        "Masked matches cannot consume the search limit",
        arguments: ClipSearchQuery.Mode.allCases, [false, true])
    func searchLimit(mode: ClipSearchQuery.Mode, liveGrant: Bool) async throws {
        let store = try MCPTestStore.make()
        let safe = ClipItem(
            createdAt: Date(timeIntervalSince1970: 1), kind: .text,
            preview: "limitfixture safe", contentHash: "limitfixture-safe")
        let masked = ClipItem(
            createdAt: Date(timeIntervalSince1970: 2), kind: .jwt,
            preview: "limitfixture masked", contentHash: "limitfixture-masked")
        for item in [safe, masked] {
            try await store.insert(item, content: .text(item.preview))
        }
        let grant = MCPClientGrant(
            clientName: "Synthetic test client", scope: .all,
            contextPack: MCPContextPack(name: "Test selection", clipIDs: [safe.id, masked.id]))
        let runner =
            liveGrant
            ? MCPToolRunner(store: store, grantProvider: { .active(grant) })
            : MCPToolRunner(store: store, scope: .all)
        let result = try resultJSON(
            await runner.call(
                tool: "search_clips",
                arguments: .object([
                    "query": .string("limitfixture"), "mode": .string(mode.rawValue),
                    "limit": .int(1)
                ])))
        #expect(result["count"]?.intValue == 1)
        #expect(result["clips"]?.arrayValue?.first?["id"]?.stringValue == safe.id.uuidString)
    }

}

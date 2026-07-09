import Foundation
import GanchoKit
import Testing

@testable import GanchoMCP

@Suite("MCP tool runner — scope, veto, logging")
struct MCPToolRunnerTests {
    private func runner(_ scope: MCPAccessScope, sink: EventSink) async throws -> MCPToolRunner {
        let store = try MCPTestStore.make()
        try await store.seedFixtures()
        return MCPToolRunner(store: store, scope: scope) { await sink.record($0) }
    }

    // MARK: - search_clips

    @Test("search returns matches and never sensitive clips")
    func searchExcludesSensitive() async throws {
        let sink = EventSink()
        let runner = try await runner(.all, sink: sink)
        let result = await runner.call(
            tool: "search_clips", arguments: .object(["query": .string("alpha")]))
        let json = try resultJSON(result)
        // Three fixtures contain "alpha"; the sensitive one is filtered out.
        #expect(json["count"]?.intValue == 2)
        let ids = (json["clips"]?.arrayValue ?? []).compactMap { $0["id"]?.stringValue }
        #expect(!ids.contains(Fixture.secret.uuidString))
    }

    @Test("boards scope limits search to pinned clips")
    func searchBoardsScope() async throws {
        let sink = EventSink()
        let runner = try await runner(.boards, sink: sink)
        let result = await runner.call(
            tool: "search_clips", arguments: .object(["query": .string("alpha")]))
        let json = try resultJSON(result)
        #expect(json["count"]?.intValue == 1)
        #expect(json["clips"]?.arrayValue?.first?["id"]?.stringValue == Fixture.pinned.uuidString)
    }

    // MARK: - get_clip

    @Test("all scope returns the content body")
    func getClipAll() async throws {
        let sink = EventSink()
        let runner = try await runner(.all, sink: sink)
        let result = await runner.call(
            tool: "get_clip", arguments: .object(["id": .string(Fixture.plain.uuidString)]))
        let json = try resultJSON(result)
        #expect(json["contentWithheld"]?.boolValue == false)
        #expect(json["content"]?.stringValue == "alpha apple body")
    }

    @Test("metadata scope withholds the content body")
    func getClipMetadataWithholds() async throws {
        let sink = EventSink()
        let runner = try await runner(.metadata, sink: sink)
        let result = await runner.call(
            tool: "get_clip", arguments: .object(["id": .string(Fixture.plain.uuidString)]))
        let json = try resultJSON(result)
        #expect(json["contentWithheld"]?.boolValue == true)
        #expect(json["content"] == .null || json["content"] == nil)
        #expect(await sink.events.last?.wasDenied == true)
    }

    @Test("boards scope serves pinned content but withholds unpinned")
    func getClipBoardsScope() async throws {
        let sink = EventSink()
        let runner = try await runner(.boards, sink: sink)

        let pinned = try resultJSON(
            await runner.call(
                tool: "get_clip", arguments: .object(["id": .string(Fixture.pinned.uuidString)])))
        #expect(pinned["content"]?.stringValue == "alpha pinned body")

        let plain = try resultJSON(
            await runner.call(
                tool: "get_clip", arguments: .object(["id": .string(Fixture.plain.uuidString)])))
        #expect(plain["contentWithheld"]?.boolValue == true)
    }

    @Test("sensitive clips are denied even under all scope")
    func getClipSensitiveDenied() async throws {
        let sink = EventSink()
        let runner = try await runner(.all, sink: sink)
        let result = await runner.call(
            tool: "get_clip", arguments: .object(["id": .string(Fixture.secret.uuidString)]))
        #expect(result.isError == true)
        #expect(await sink.events.last?.wasDenied == true)
    }

    @Test("unknown id is a readable error, not a crash")
    func getClipUnknownID() async throws {
        let sink = EventSink()
        let runner = try await runner(.all, sink: sink)
        let result = await runner.call(
            tool: "get_clip", arguments: .object(["id": .string(UUID().uuidString)]))
        #expect(result.isError == true)
    }

    // MARK: - create_pin

    @Test("create_pin pins the clip")
    func createPinPins() async throws {
        let sink = EventSink()
        let store = try MCPTestStore.make()
        try await store.seedFixtures()
        let runner = MCPToolRunner(store: store, scope: .metadata) { await sink.record($0) }

        let result = await runner.call(
            tool: "create_pin", arguments: .object(["id": .string(Fixture.plain.uuidString)]))
        #expect(try resultJSON(result)["pinned"]?.boolValue == true)
        #expect(try await store.item(id: Fixture.plain)?.isPinned == true)
    }

    @Test("create_pin with a board name creates and assigns it")
    func createPinWithBoard() async throws {
        let sink = EventSink()
        let store = try MCPTestStore.make()
        try await store.seedFixtures()
        let runner = MCPToolRunner(store: store, scope: .all) { await sink.record($0) }

        let result = await runner.call(
            tool: "create_pin",
            arguments: .object([
                "id": .string(Fixture.plain.uuidString), "board": .string("Work")
            ]))
        #expect(try resultJSON(result)["board"]?.stringValue == "Work")
        #expect(try await store.pinboards().contains { $0.name == "Work" })
    }

    @Test("create_pin refuses sensitive clips")
    func createPinSensitiveDenied() async throws {
        let sink = EventSink()
        let runner = try await runner(.all, sink: sink)
        let result = await runner.call(
            tool: "create_pin", arguments: .object(["id": .string(Fixture.secret.uuidString)]))
        #expect(result.isError == true)
        #expect(await sink.events.last?.wasDenied == true)
    }

    // MARK: - paste_stack

    @Test("paste_stack assembles ordered content under all scope")
    func pasteStackAll() async throws {
        let sink = EventSink()
        let runner = try await runner(.all, sink: sink)
        let result = await runner.call(
            tool: "paste_stack",
            arguments: .object([
                "ids": .array([
                    .string(Fixture.pinned.uuidString), .string(Fixture.plain.uuidString)
                ])
            ]))
        let json = try resultJSON(result)
        #expect(json["count"]?.intValue == 2)
        #expect(json["combinedText"]?.stringValue == "alpha pinned body\n\nalpha apple body")
    }

    @Test("paste_stack drops sensitive clips silently")
    func pasteStackExcludesSensitive() async throws {
        let sink = EventSink()
        let runner = try await runner(.all, sink: sink)
        let result = await runner.call(
            tool: "paste_stack",
            arguments: .object([
                "ids": .array([
                    .string(Fixture.plain.uuidString), .string(Fixture.secret.uuidString)
                ])
            ]))
        #expect(try resultJSON(result)["count"]?.intValue == 1)
    }

    @Test("paste_stack is denied under metadata scope")
    func pasteStackMetadataDenied() async throws {
        let sink = EventSink()
        let runner = try await runner(.metadata, sink: sink)
        let result = await runner.call(
            tool: "paste_stack",
            arguments: .object(["ids": .array([.string(Fixture.plain.uuidString)])]))
        #expect(result.isError == true)
        #expect(await sink.events.last?.wasDenied == true)
    }

    // MARK: - list_boards

    @Test("list_boards returns board metadata and is allowed under metadata scope")
    func listBoardsMetadataScope() async throws {
        let sink = EventSink()
        let store = try MCPTestStore.make()
        try await store.seedFixtures()
        try await store.createPinboard(name: "Work", sfSymbol: "briefcase")
        let runner = MCPToolRunner(store: store, scope: .metadata) { await sink.record($0) }

        let result = await runner.call(tool: "list_boards", arguments: .object([:]))
        #expect(result.isError == false)
        let json = try resultJSON(result)
        // The migration-seeded Favorites board plus the one created above.
        #expect(json["count"]?.intValue == 2)
        let boards = json["boards"]?.arrayValue ?? []
        let names = boards.compactMap { $0["name"]?.stringValue }
        #expect(names.contains("Favorites"))
        #expect(names.contains("Work"))
        let symbols = boards.compactMap { $0["sfSymbol"]?.stringValue }
        #expect(symbols.contains("briefcase"))
    }

    @Test("list_boards is logged with tool, scope, and board count")
    func listBoardsLogged() async throws {
        let sink = EventSink()
        let runner = try await runner(.boards, sink: sink)
        _ = await runner.call(tool: "list_boards", arguments: .object([:]))
        let event = await sink.events.last
        #expect(event?.tool == .listBoards)
        #expect(event?.scope == .boards)
        #expect(event?.resultCount == 1)  // just the seeded Favorites board
        #expect(event?.wasDenied == false)
    }

    // MARK: - logging + dispatch

    @Test("every call is logged with tool and scope")
    func logsAccess() async throws {
        let sink = EventSink()
        let runner = try await runner(.all, sink: sink)
        _ = await runner.call(
            tool: "search_clips", arguments: .object(["query": .string("alpha")]))
        let event = await sink.events.last
        #expect(event?.tool == .searchClips)
        #expect(event?.scope == .all)
        #expect(event?.resultCount == 2)
        #expect(event?.wasDenied == false)
    }

    @Test("unknown tool name is a readable error")
    func unknownTool() async throws {
        let sink = EventSink()
        let runner = try await runner(.all, sink: sink)
        let result = await runner.call(tool: "delete_everything", arguments: .object([:]))
        #expect(result.isError == true)
        // Unknown tools are not logged (no MCPToolName to attribute them to).
        #expect(await sink.events.isEmpty)
    }
}

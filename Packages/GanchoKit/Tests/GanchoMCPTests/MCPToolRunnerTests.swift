import Foundation
import GanchoKit
import Testing

@testable import GanchoMCP

// One @Test per enforcement rule keeps the security surface readable; the
// struct legitimately exceeds the default body-length budget as a result.
// swiftlint:disable type_body_length
@Suite("MCP tool runner — scope, veto, logging")
struct MCPToolRunnerTests {
    private func runner(
        _ scope: MCPAccessScope,
        accessMode: MCPAccessMode = .readWrite,
        sink: EventSink
    ) async throws -> MCPToolRunner {
        let store = try MCPTestStore.make()
        try await store.seedFixtures()
        return MCPToolRunner(store: store, scope: scope, accessMode: accessMode) {
            await sink.record($0)
        }
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

    @Test("boards scope also includes unpinned clips deliberately assigned to a board")
    func searchBoardsScopeIncludesBoardMembers() async throws {
        let sink = EventSink()
        let store = try MCPTestStore.make()
        try await store.seedFixtures()
        try await store.assign(clipID: Fixture.plain, toBoard: Pinboard.favoritesID)
        let runner = MCPToolRunner(store: store, scope: .boards) { await sink.record($0) }

        let result = await runner.call(
            tool: "search_clips", arguments: .object(["query": .string("alpha")]))
        let ids = Set(
            (try resultJSON(result)["clips"]?.arrayValue ?? [])
                .compactMap { $0["id"]?.stringValue })

        #expect(ids == Set([Fixture.plain.uuidString, Fixture.pinned.uuidString]))
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
        let runner = MCPToolRunner(store: store, scope: .metadata, accessMode: .readWrite) {
            await sink.record($0)
        }

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
        let runner = MCPToolRunner(store: store, scope: .all, accessMode: .readWrite) {
            await sink.record($0)
        }

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

    @Test("paste_stack rejects oversized batches before reading clips")
    func pasteStackRejectsOversizedBatch() async throws {
        let sink = EventSink()
        let runner = try await runner(.all, sink: sink)
        let ids = Array(
            repeating: JSONValue.string(Fixture.plain.uuidString),
            count: MCPToolRunner.maximumPasteStackClips + 1)

        let result = await runner.call(
            tool: "paste_stack", arguments: .object(["ids": .array(ids)]))

        #expect(result.isError == true)
        #expect(await sink.events.last?.denialReason == .invalidArguments)
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

    // MARK: - Live client grants

    @Test("live revoke interrupts the next call and records the client-safe reason")
    func liveRevoke() async throws {
        let sink = EventSink()
        let store = try MCPTestStore.make()
        try await store.seedFixtures()
        try await store.assign(clipID: Fixture.plain, toBoard: Pinboard.favoritesID)
        var grant = liveGrant(scope: .all)
        let box = GrantResolutionBox(.active(grant))
        let runner = MCPToolRunner(
            store: store,
            grantProvider: { await box.get() },
            log: { await sink.record($0) })

        let first = await runner.call(
            tool: "get_clip", arguments: .object(["id": .string(Fixture.plain.uuidString)]))
        #expect(first.isError == false)

        grant.revokedAt = Date()
        await box.set(.revoked(grant))
        let second = await runner.call(
            tool: "get_clip", arguments: .object(["id": .string(Fixture.plain.uuidString)]))

        #expect(second.isError == true)
        #expect(await sink.events.last?.grantID == grant.id)
        #expect(await sink.events.last?.clientName == "Claude Desktop")
        #expect(await sink.events.last?.denialReason == .grantRevoked)
    }

    @Test("missing expired revoked disabled and contextless grants fail closed")
    func invalidGrantStates() async throws {
        let store = try MCPTestStore.make()
        try await store.seedFixtures()
        let grant = liveGrant(scope: .all)
        let states: [(MCPGrantResolution, MCPAccessDenialReason)] = [
            (.missing, .grantMissing),
            (.expired(grant), .grantExpired),
            (.revoked(grant), .grantRevoked),
            (.disabled(grant), .serverDisabled),
            (.invalidContext(grant), .outsideContext)
        ]

        for (resolution, expectedReason) in states {
            let sink = EventSink()
            let runner = MCPToolRunner(
                store: store,
                grantProvider: { resolution },
                log: { await sink.record($0) })
            let result = await runner.call(
                tool: "search_clips", arguments: .object(["query": .string("alpha")]))
            #expect(result.isError == true)
            #expect(await sink.events.last?.denialReason == expectedReason)
        }
    }

    @Test("read-only clients cannot mutate the store")
    func readOnlyDeniesCreatePin() async throws {
        let sink = EventSink()
        let store = try MCPTestStore.make()
        try await store.seedFixtures()
        try await store.assign(clipID: Fixture.plain, toBoard: Pinboard.favoritesID)
        let grant = liveGrant(scope: .all, accessMode: .readOnly)
        let runner = MCPToolRunner(
            store: store,
            grantProvider: { .active(grant) },
            log: { await sink.record($0) })

        let result = await runner.call(
            tool: "create_pin", arguments: .object(["id": .string(Fixture.plain.uuidString)]))

        #expect(result.isError == true)
        #expect(try await store.item(id: Fixture.plain)?.isPinned == false)
        #expect(await sink.events.last?.denialReason == .readOnly)
    }

    @Test("the convenience initializer defaults to read-only (least privilege)")
    func convenienceInitDefaultsToReadOnly() async throws {
        // Guards the fail-closed default: an embedded caller that omits
        // accessMode must never silently gain write access.
        let sink = EventSink()
        let store = try MCPTestStore.make()
        try await store.seedFixtures()
        let runner = MCPToolRunner(store: store, scope: .all) { await sink.record($0) }

        let result = await runner.call(
            tool: "create_pin", arguments: .object(["id": .string(Fixture.plain.uuidString)]))

        #expect(result.isError == true)
        #expect(try await store.item(id: Fixture.plain)?.isPinned == false)
        #expect(await sink.events.last?.denialReason == .readOnly)
    }

    @Test("explicit board and time context filters search and direct reads")
    func boardAndTimeContext() async throws {
        let sink = EventSink()
        let store = try MCPTestStore.make()
        let now = Date(timeIntervalSince1970: 100_000)
        let recent = ClipItem(
            id: UUID(), createdAt: now.addingTimeInterval(-30 * 60),
            preview: "context recent", contentHash: "context-recent")
        let old = ClipItem(
            id: UUID(), createdAt: now.addingTimeInterval(-2 * 60 * 60),
            preview: "context old", contentHash: "context-old")
        let outside = ClipItem(
            id: UUID(), createdAt: now.addingTimeInterval(-10 * 60),
            preview: "context outside", contentHash: "context-outside")
        for item in [recent, old, outside] {
            try await store.insert(item, content: .text(item.preview))
        }
        try await store.assign(clipID: recent.id, toBoard: Pinboard.favoritesID)
        try await store.assign(clipID: old.id, toBoard: Pinboard.favoritesID)
        let grant = MCPClientGrant(
            clientName: "Claude Desktop",
            scope: .all,
            contextPack: MCPContextPack(
                name: "Recent Favorites",
                boardID: Pinboard.favoritesID,
                boardName: "Favorites",
                timeScope: .lastHour))
        let runner = MCPToolRunner(
            store: store,
            grantProvider: { .active(grant) },
            log: { await sink.record($0) },
            now: { now })

        let search = try resultJSON(
            await runner.call(
                tool: "search_clips", arguments: .object(["query": .string("context")])))
        let ids = search["clips"]?.arrayValue?.compactMap { $0["id"]?.stringValue } ?? []
        #expect(ids == [recent.id.uuidString])

        let oldRead = await runner.call(
            tool: "get_clip", arguments: .object(["id": .string(old.id.uuidString)]))
        let outsideRead = await runner.call(
            tool: "get_clip", arguments: .object(["id": .string(outside.id.uuidString)]))
        #expect(oldRead.isError == true)
        #expect(outsideRead.isError == true)
    }

    @Test("sensitive veto still wins inside an explicit all-content context")
    func liveContextSensitiveVeto() async throws {
        let sink = EventSink()
        let store = try MCPTestStore.make()
        try await store.seedFixtures()
        try await store.assign(clipID: Fixture.secret, toBoard: Pinboard.favoritesID)
        let grant = liveGrant(scope: .all)
        let runner = MCPToolRunner(
            store: store,
            grantProvider: { .active(grant) },
            log: { await sink.record($0) })

        let result = await runner.call(
            tool: "get_clip", arguments: .object(["id": .string(Fixture.secret.uuidString)]))

        #expect(result.isError == true)
        #expect(await sink.events.last?.denialReason == .sensitive)
    }

    @Test("outside-context denial does not reveal whether a clip is sensitive")
    func outsideContextPrecedesSensitiveVeto() async throws {
        let sink = EventSink()
        let store = try MCPTestStore.make()
        try await store.seedFixtures()
        let grant = liveGrant(scope: .all)
        let runner = MCPToolRunner(
            store: store,
            grantProvider: { .active(grant) },
            log: { await sink.record($0) })

        let read = await runner.call(
            tool: "get_clip", arguments: .object(["id": .string(Fixture.secret.uuidString)]))
        let pin = await runner.call(
            tool: "create_pin", arguments: .object(["id": .string(Fixture.secret.uuidString)]))

        #expect(read.isError == true)
        #expect(pin.isError == true)
        let reasons = await sink.events.suffix(2).map(\.denialReason)
        #expect(reasons == [.outsideContext, .outsideContext])
    }

    @Test("curated search filters ids before applying the result limit")
    func curatedSearchAppliesContextBeforeLimit() async throws {
        let store = try MCPTestStore.make()
        let allowed = ClipItem(preview: "curated match", contentHash: "curated-allowed")
        let ambient = ClipItem(preview: "curated match", contentHash: "curated-ambient")
        try await store.insert(ambient, content: .text(ambient.preview))
        try await store.insert(allowed, content: .text(allowed.preview))
        let grant = MCPClientGrant(
            clientName: "Curated client",
            scope: .all,
            contextPack: MCPContextPack(name: "Selection", clipIDs: [allowed.id]))
        let runner = MCPToolRunner(store: store, grantProvider: { .active(grant) })

        let result = try resultJSON(
            await runner.call(
                tool: "search_clips",
                arguments: .object(["query": .string("curated"), "limit": .int(1)])))

        #expect(
            result["clips"]?.arrayValue?.map { $0["id"]?.stringValue } == [allowed.id.uuidString])
    }

    private func liveGrant(
        scope: MCPAccessScope,
        accessMode: MCPAccessMode = .readWrite
    ) -> MCPClientGrant {
        MCPClientGrant(
            clientName: "Claude Desktop",
            scope: scope,
            accessMode: accessMode,
            contextPack: MCPContextPack(
                name: "Favorites",
                boardID: Pinboard.favoritesID,
                boardName: "Favorites"))
    }
}
// swiftlint:enable type_body_length

private actor GrantResolutionBox {
    private var resolution: MCPGrantResolution

    init(_ resolution: MCPGrantResolution) { self.resolution = resolution }

    func get() -> MCPGrantResolution { resolution }
    func set(_ resolution: MCPGrantResolution) { self.resolution = resolution }
}

import Foundation
import GanchoKit
import Testing

@testable import GanchoMCP

@Suite("MCP access ledger — the grant's context at call time and the live signal")
struct MCPAccessLedgerTests {
    private struct WriteFailed: Error {}

    private actor SignalCounter {
        private(set) var count = 0
        func bump() { count += 1 }
    }

    @Test("a board grant's call records its board and window")
    func runnerRecordsBoardContext() async throws {
        let store = try MCPTestStore.make()
        try await store.seedFixtures()
        try await store.assign(clipID: Fixture.plain, toBoard: Pinboard.favoritesID)
        let grant = MCPClientGrant(
            clientName: "Claude Desktop", scope: .all,
            contextPack: MCPContextPack(
                name: "Favorites", boardID: Pinboard.favoritesID, timeScope: .lastWeek))
        let sink = EventSink()
        let runner = MCPToolRunner(
            store: store, grantProvider: { .active(grant) }, log: { await sink.record($0) })

        _ = await runner.call(
            tool: "get_clip", arguments: .object(["id": .string(Fixture.plain.uuidString)]))

        let event = try #require(await sink.events.last)
        #expect(event.resultCount == 1)
        #expect(
            event.context
                == MCPAccessContext(boardID: Pinboard.favoritesID, timeScope: .lastWeek))
    }

    @Test("a curated selection records its size, not its clip ids")
    func curatedContextIsACount() {
        let ids: Set<UUID> = [UUID(), UUID(), UUID()]
        let context = MCPAccessContext(
            MCPContextPack(name: "Selected", clipIDs: ids, timeScope: .lastDay))
        #expect(context == MCPAccessContext(clipCount: 3, timeScope: .lastDay))
    }

    @Test("the context survives the ledger; a row without one reads as nil")
    func contextRoundTrips() async throws {
        let store = try MCPTestStore.make()
        let boardID = UUID()
        try await store.recordMCPAccess(
            MCPAccessEvent(
                tool: .searchClips, scope: .all, resultCount: 2,
                context: MCPAccessContext(boardID: boardID, timeScope: .lastHour),
                occurredAt: Date(timeIntervalSince1970: 2_000)))
        try await store.recordMCPAccess(
            MCPAccessEvent(
                tool: .getClip, scope: .boards, resultCount: 1,
                context: MCPAccessContext(clipCount: 4, timeScope: .allTime),
                occurredAt: Date(timeIntervalSince1970: 1_500)))
        try await store.recordMCPAccess(
            MCPAccessEvent(
                tool: .listBoards, scope: .metadata,
                occurredAt: Date(timeIntervalSince1970: 1_000)))

        let events = try await store.recentMCPAccesses(limit: 10)
        #expect(
            events.map(\.context) == [
                MCPAccessContext(boardID: boardID, timeScope: .lastHour),
                MCPAccessContext(clipCount: 4, timeScope: .allTime),
                nil
            ])
    }

    @Test("a live reader resumes after the last row it saw, oldest first")
    func readsAfterAnID() async throws {
        let store = try MCPTestStore.make()
        #expect(try await store.latestMCPAccessID() == 0)
        for count in 1...3 {
            try await store.recordMCPAccess(
                MCPAccessEvent(tool: .searchClips, scope: .all, resultCount: count))
        }
        let all = try await store.mcpAccesses(after: 0)
        #expect(all.map(\.event.resultCount) == [1, 2, 3])
        let newest = try await store.latestMCPAccessID()
        #expect(newest == all.last?.id)

        let rest = try await store.mcpAccesses(after: all[0].id)
        #expect(rest.map(\.event.resultCount) == [2, 3])
        #expect(try await store.mcpAccesses(after: newest).isEmpty)
        #expect(try await store.mcpAccesses(after: 0, limit: 2).count == 2)
        #expect(try await store.mcpAccesses(after: 0, limit: 0).isEmpty)
        #expect(try await store.mcpAccesses(after: 0, limit: -1).isEmpty)
    }

    @Test("the app is signalled after the row is written, and only then")
    func signalFollowsTheWrite() async throws {
        let store = try MCPTestStore.make()
        let counter = SignalCounter()
        let log = MCPAccessLedger.log(
            record: { try await store.recordMCPAccess($0) },
            signal: { Task { await counter.bump() } })
        let runner = MCPToolRunner(store: store, scope: .metadata, log: log)

        _ = await runner.call(tool: "list_boards", arguments: .object([:]))
        try await waitUntil { await counter.count == 1 }
        #expect(try await store.latestMCPAccessID() == 1)

        let failing = MCPAccessLedger.log(
            record: { _ in throw WriteFailed() }, signal: { Task { await counter.bump() } })
        await failing(MCPAccessEvent(tool: .listBoards, scope: .metadata))
        try await Task.sleep(for: .milliseconds(200))
        #expect(await counter.count == 1)
    }

    #if os(macOS)
        @Test("the signal is the name alone: no object, no user info")
        func signalIsContentFree() async throws {
            let received = ReceivedNotifications()
            let center = DistributedNotificationCenter.default()
            let observer = center.addObserver(
                forName: MCPAccessSignal.name, object: nil, queue: nil
            ) { note in
                received.append(object: note.object, userInfo: note.userInfo)
            }
            defer { center.removeObserver(observer) }

            MCPAccessSignal.post(to: center)
            try await waitUntil { !received.isEmpty }
            #expect(received.allContentFree)
        }
    #endif

    private func waitUntil(_ condition: @Sendable () async -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !(await condition()) {
            guard Date() < deadline else {
                Issue.record("timed out")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
    }
}

/// Collects what each delivered notification carried, from any thread.
private final class ReceivedNotifications: @unchecked Sendable {
    private let lock = NSLock()
    private var payloads: [(object: Any?, userInfo: [AnyHashable: Any]?)] = []

    var isEmpty: Bool { lock.withLock { payloads.isEmpty } }
    var allContentFree: Bool {
        lock.withLock { payloads.allSatisfy { $0.object == nil && $0.userInfo == nil } }
    }

    func append(object: Any?, userInfo: [AnyHashable: Any]?) {
        lock.withLock { payloads.append((object, userInfo)) }
    }
}

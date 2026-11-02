import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

@Suite("Agent read feed — one HUD per client burst and a dot that fades")
struct AgentReadFeedTests {
    private let start = Date(timeIntervalSince1970: 1_000_000)
    private let claude = UUID()
    private let cursor = UUID()

    private func record(
        _ id: Int64, _ tool: MCPToolName = .searchClips, grant: UUID? = nil, count: Int = 1,
        denied: Bool = false, at offset: TimeInterval = 0
    ) -> MCPAccessRecord {
        MCPAccessRecord(
            id: id,
            event: MCPAccessEvent(
                tool: tool, scope: .all, grantID: grant ?? claude,
                clientName: grant == cursor ? "Cursor" : "Claude", resultCount: count,
                wasDenied: denied, denialReason: denied ? .scope : nil,
                context: MCPAccessContext(boardID: nil, timeScope: .lastWeek),
                occurredAt: start.addingTimeInterval(offset)))
    }

    @Test("rows up to the launch baseline never show")
    func baselineIsSkipped() {
        var feed = AgentReadFeed(lastSeenID: 5)
        #expect(feed.ingest([record(4, count: 3), record(5, count: 2)], now: start) == nil)
        #expect(!feed.showsDot(at: start))
        #expect(feed.lastSeenID == 5)
    }

    @Test("denials, board listings and empty results stay in the ledger only")
    func quietRows() {
        var feed = AgentReadFeed(lastSeenID: 0)
        let notice = feed.ingest(
            [
                record(1, denied: true), record(2, .listBoards, count: 4),
                record(3, count: 0)
            ], now: start)
        #expect(notice == nil)
        #expect(!feed.showsDot(at: start))
        #expect(feed.lastSeenID == 3, "skipped rows are still consumed")
    }

    @Test("one client's calls within the window add up")
    func burstAddsUp() throws {
        var feed = AgentReadFeed(lastSeenID: 0)
        _ = feed.ingest([record(1, count: 2)], now: start)
        let later = start.addingTimeInterval(AgentReadFeed.window)
        let burst = feed.ingest(
            [record(2, .getClip, at: AgentReadFeed.window), record(3, .createPin, count: 0)],
            now: later)
        let notice = try #require(burst)
        #expect(notice.reads == 3)
        #expect(notice.pins == 1)
        #expect(notice.clientName == "Claude")
        #expect(notice.startedAt == start)
    }

    @Test("past the window, or from another client, a new HUD starts")
    func newBurst() throws {
        var feed = AgentReadFeed(lastSeenID: 0)
        _ = feed.ingest([record(1, count: 2)], now: start)
        let past = AgentReadFeed.window + 1
        let next = feed.ingest([record(2, count: 1, at: past)], now: start.addingTimeInterval(past))
        let late = try #require(next)
        #expect(late.reads == 1)

        let fromCursor = feed.ingest(
            [record(3, grant: cursor, count: 4, at: past)], now: start.addingTimeInterval(past))
        let other = try #require(fromCursor)
        #expect(other.reads == 4)
        #expect(other.grantID == cursor)
    }

    @Test("a row older than the dot's life is consumed without a HUD")
    func staleRow() {
        var feed = AgentReadFeed(lastSeenID: 0)
        let now = start.addingTimeInterval(AgentReadFeed.dotDuration + 1)
        #expect(feed.ingest([record(1, count: 2)], now: now) == nil)
        #expect(feed.lastSeenID == 1)
    }

    @Test("the dot lasts its duration, or until the menu opens")
    func dotLifetime() {
        var feed = AgentReadFeed(lastSeenID: 0)
        _ = feed.ingest([record(1)], now: start)
        #expect(feed.showsDot(at: start.addingTimeInterval(AgentReadFeed.dotDuration - 1)))
        #expect(!feed.showsDot(at: start.addingTimeInterval(AgentReadFeed.dotDuration)))

        _ = feed.ingest([record(2, at: 1)], now: start.addingTimeInterval(1))
        feed.clearDot()
        #expect(!feed.showsDot(at: start.addingTimeInterval(2)))
    }
}

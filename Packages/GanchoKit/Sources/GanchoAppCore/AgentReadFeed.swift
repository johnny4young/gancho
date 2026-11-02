import Foundation
import GanchoKit

/// Folds new MCP ledger rows into the menu-bar dot and the agent-read HUD.
/// Reads that exposed clips and pins count; denials, board listings and empty
/// results stay in the ledger only.
public struct AgentReadFeed: Sendable {
    /// One client's calls within this span add up in a single HUD.
    public static let window: TimeInterval = 5
    public static let dotDuration: TimeInterval = 120

    public struct Notice: Sendable, Equatable {
        public var grantID: UUID?
        public var clientName: String?
        public var reads: Int
        public var pins: Int
        public var context: MCPAccessContext?
        public var startedAt: Date
        public var occurredAt: Date
    }

    public private(set) var lastSeenID: Int64
    public private(set) var dotUntil: Date?
    private var notice: Notice?

    /// `lastSeenID` is the newest row at launch, so older reads never show.
    public init(lastSeenID: Int64) {
        self.lastSeenID = lastSeenID
    }

    /// The HUD to show for `records`, or nil when none of them earns one.
    public mutating func ingest(_ records: [MCPAccessRecord], now: Date) -> Notice? {
        var changed = false
        for record in records where record.id > lastSeenID {
            lastSeenID = record.id
            let event = record.event
            guard !event.wasDenied, now.timeIntervalSince(event.occurredAt) <= Self.dotDuration
            else { continue }
            let reads = event.tool.exposesClips ? event.resultCount : 0
            let pins = event.tool.mutatesStore ? 1 : 0
            guard reads + pins > 0 else { continue }
            if var current = notice, current.grantID == event.grantID,
                event.occurredAt.timeIntervalSince(current.startedAt) <= Self.window
            {
                current.reads += reads
                current.pins += pins
                current.context = event.context
                current.occurredAt = event.occurredAt
                notice = current
            } else {
                notice = Notice(
                    grantID: event.grantID,
                    clientName: event.clientName,
                    reads: reads, pins: pins, context: event.context,
                    startedAt: event.occurredAt, occurredAt: event.occurredAt)
            }
            changed = true
        }
        guard changed else { return nil }
        dotUntil = now.addingTimeInterval(Self.dotDuration)
        return notice
    }

    public func showsDot(at now: Date) -> Bool {
        dotUntil.map { now < $0 } ?? false
    }

    /// Opening the menu acknowledges the read.
    public mutating func clearDot() {
        dotUntil = nil
    }
}

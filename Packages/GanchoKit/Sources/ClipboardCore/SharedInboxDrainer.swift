import Foundation

/// A running flag spans suspension: actor isolation alone would allow another
/// drain to reenter during commit. Batches are bounded and deferred candidates
/// rotate via a metadata cursor, without a busy retry loop or content logging.
public actor SharedInboxDrainer {
    public struct Report: Sendable, Equatable {
        public var acknowledged = 0
        public var failed = 0
        public var poisoned = 0
        public var deferred = 0
        public var undeletable = 0
        public var isBusy = false
    }

    private var running = false
    private var cursor: SharedInbox.Cursor?
    private let batchSize: Int

    public init(batchSize: Int = 64) { self.batchSize = batchSize }

    public func drain(
        _ inbox: SharedInbox,
        commit: @Sendable (SharedInbox.Delivery) async throws -> Void
    ) async throws -> Report {
        guard !running else { return Report(isBusy: true) }
        running = true
        defer { running = false }
        try Task.checkCancellation()
        let read = try inbox.readPending(after: cursor, limit: batchSize)
        cursor = read.nextCursor
        var report = Report(
            poisoned: read.poisoned, deferred: read.deferred, undeletable: read.undeletable)
        for delivery in read.deliveries {
            guard !Task.isCancelled else { break }
            do { try await commit(delivery) } catch {
                report.failed += 1
                continue
            }
            guard !Task.isCancelled else { break }
            do {
                try inbox.acknowledge(delivery)
                report.acknowledged += 1
            } catch { report.undeletable += 1 }
        }
        return report
    }
}

import Foundation

/// A running flag spans suspension: actor isolation alone would allow another
/// drain to reenter during commit. Each drain sweeps the whole inbox once in
/// small batches, so memory stays bounded without leaving later files queued.
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
    private var rerunRequested = false
    private let batchSize: Int

    public init(batchSize: Int = 8) { self.batchSize = batchSize }

    /// A call that arrives mid-drain returns `isBusy` and makes the running
    /// drain sweep again, so a deposit after its scan is not left for later.
    public func drain(
        _ inbox: SharedInbox,
        commit: @Sendable (SharedInbox.Delivery) async throws -> Void
    ) async throws -> Report {
        guard !running else {
            rerunRequested = true
            return Report(isBusy: true)
        }
        running = true
        defer { running = false }
        var report = Report()
        repeat {
            rerunRequested = false
            guard try await sweep(inbox, commit: commit, into: &report) else { break }
        } while rerunRequested
        return report
    }

    /// False when cancelled mid-sweep; unacknowledged files stay queued.
    private func sweep(
        _ inbox: SharedInbox,
        commit: @Sendable (SharedInbox.Delivery) async throws -> Void,
        into report: inout Report
    ) async throws -> Bool {
        var cursor: SharedInbox.Cursor?
        repeat {
            try Task.checkCancellation()
            let read = try inbox.readPending(after: cursor, limit: batchSize)
            cursor = read.nextCursor
            report.poisoned += read.poisoned
            report.deferred += read.deferred
            report.undeletable += read.undeletable
            for delivery in read.deliveries {
                guard !Task.isCancelled else { return false }
                do { try await commit(delivery) } catch {
                    report.failed += 1
                    continue
                }
                guard !Task.isCancelled else { return false }
                do {
                    try inbox.acknowledge(delivery)
                    report.acknowledged += 1
                } catch { report.undeletable += 1 }
            }
        } while cursor != nil
        return true
    }
}

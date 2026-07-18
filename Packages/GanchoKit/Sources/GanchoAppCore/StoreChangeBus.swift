import Foundation

/// A content-free store-mutation event. Never carries clip data — only the
/// FACT that a category of state changed, so downstream reconcilers
/// (Spotlight donation, widget timelines, list refreshes) know they may be
/// stale. This is the signal that closes the "I forgot to refresh X after
/// mutating Y" class of bug: the mutation site posts once, and every consumer
/// that cares is already subscribed.
public enum StoreChange: String, Sendable, Equatable, CaseIterable {
    /// A clip was inserted, edited, or deleted.
    case clips
    /// A board was created, renamed, deleted, or its membership changed.
    case boards
    /// Curation changed: promote/demote to snippet, pin/unpin.
    case curation
}

/// A coalesced batch of distinct changes from one burst — order-independent,
/// so a reconciler reacts once to the union rather than N times to a stream.
public typealias StoreChangeBatch = Set<StoreChange>

/// Fans store-mutation events out to any number of subscribers, each as its
/// own `AsyncStream`. `@unchecked Sendable` is sound: all mutable state
/// (`continuations`) is guarded by a lock, and only content-free enum values
/// cross the boundary.
public final class StoreChangeBus: @unchecked Sendable {
    private let lock = NSLock()
    private var continuations: [UUID: AsyncStream<StoreChange>.Continuation] = [:]

    public init() {}

    /// A new subscription. The stream ends when the returned value is
    /// deallocated or the task is cancelled; the bus drops its continuation on
    /// termination, so subscribers never leak.
    public func subscribe() -> AsyncStream<StoreChange> {
        let id = UUID()
        return AsyncStream { continuation in
            lock.lock()
            continuations[id] = continuation
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                lock.lock()
                continuations[id] = nil
                lock.unlock()
            }
        }
    }

    /// Broadcast one change to every current subscriber.
    public func post(_ change: StoreChange) {
        lock.lock()
        let targets = Array(continuations.values)
        lock.unlock()
        for continuation in targets {
            continuation.yield(change)
        }
    }

    /// Broadcast several changes (a batch mutation posts its whole set at once).
    public func post(_ changes: StoreChangeBatch) {
        for change in changes {
            post(change)
        }
    }

    /// Subscriber count — for tests and diagnostics only (content-free).
    public var subscriberCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return continuations.count
    }
}

/// The debounce state behind `StoreChangeCoalescer`, extracted as a
/// deterministic actor so the coalescing rule is unit-tested WITHOUT any
/// timing: each incoming change accumulates into the pending union and bumps a
/// generation; a flush only wins if its generation is still current (no newer
/// change raced in), at which point it returns the union and clears it.
public actor StoreChangeAccumulator {
    private var pending: StoreChangeBatch = []
    private var generation = 0

    public init() {}

    /// Accumulate a change; the returned generation is the flush's ticket.
    public func add(_ change: StoreChange) -> Int {
        pending.insert(change)
        generation += 1
        return generation
    }

    /// Returns the accumulated union and clears it ONLY if `ticket` is still
    /// the latest generation — otherwise nil (a newer change is pending, so
    /// this stale flush must not fire).
    public func flush(ticket: Int) -> StoreChangeBatch? {
        guard ticket == generation, !pending.isEmpty else { return nil }
        let batch = pending
        pending = []
        return batch
    }
}

/// Coalesces a stream of `StoreChange` into debounced batches: accumulates
/// events until `window` of quiet passes, then emits their union ONCE. A batch
/// delete of 50 clips becomes one reconcile, not fifty. The sleep is injected
/// so tests can drive timing deterministically.
public struct StoreChangeCoalescer: Sendable {
    let window: Duration
    let sleep: @Sendable (Duration) async throws -> Void

    public init(
        window: Duration = .milliseconds(300),
        sleep: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        }
    ) {
        self.window = window
        self.sleep = sleep
    }

    /// Emits one `StoreChangeBatch` per quiet-separated burst of `source`.
    public func batches(
        of source: AsyncStream<StoreChange>
    ) -> AsyncStream<StoreChangeBatch> {
        let accumulator = StoreChangeAccumulator()
        let sleep = self.sleep
        let window = self.window
        return AsyncStream { continuation in
            let task = Task {
                var debounceTask: Task<Void, Never>?
                for await change in source {
                    let ticket = await accumulator.add(change)
                    debounceTask?.cancel()
                    debounceTask = Task {
                        guard (try? await sleep(window)) != nil,
                            !Task.isCancelled
                        else { return }
                        if let batch = await accumulator.flush(ticket: ticket) {
                            continuation.yield(batch)
                        }
                    }
                }
                if Task.isCancelled { debounceTask?.cancel() }
                await debounceTask?.value
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}

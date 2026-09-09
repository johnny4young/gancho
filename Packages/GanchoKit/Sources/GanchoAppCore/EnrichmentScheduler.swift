import Foundation

/// Caps how many enrichments run at once.
///
/// Enrichment is dispatched per capture as an unstructured `Task`, and nothing
/// counted them. Capture is throttled — the macOS poll is 250 ms and coalesces
/// reads — but on-device inference takes seconds, so a burst of copies can
/// leave a growing pile of them in flight, each holding its own model session
/// and competing for the same Neural Engine. More at once does not finish the
/// pile sooner; it just makes every one of them slower and the memory higher.
///
/// Waiters are served in COPY order, keyed on the capture time the caller
/// passes in — not on the order their tasks happened to reach this actor.
/// That distinction is the whole reason the key exists: both shells dispatch
/// enrichment as an unstructured `Task`, and Swift makes no promise those run
/// in creation order, so a later copy can arrive here first. It matters most
/// exactly where the pile forms — an iOS share-extension inbox drains as a
/// burst of back-to-back tasks — and enrichment decorates a clip the user just
/// copied, so the one copied first is the one they are most likely to be
/// looking for.
///
/// Ordering applies to waiters only: work that arrives while a slot is free
/// starts immediately, because there is nothing to order it against yet.
public actor EnrichmentScheduler {
    /// Two, not one: the stages within a single enrichment are serial (OCR,
    /// then title, then embedding), so a second slot keeps the engine busy
    /// while the first is between stages. Beyond that they mostly contend.
    public static let defaultLimit = 2

    private struct Waiter {
        /// Identity for cancellation removal — `copiedAt` can tie.
        let id: UInt64
        /// The caller's place in line: when the clip was copied.
        let copiedAt: Date
        /// `true` = a slot was handed over, `false` = cancelled while parked.
        let continuation: CheckedContinuation<Bool, Never>
    }

    private let limit: Int
    private var running = 0
    private var waiting: [Waiter] = []
    private var nextWaiterID: UInt64 = 0

    public init(limit: Int = EnrichmentScheduler.defaultLimit) {
        self.limit = max(1, limit)
    }

    /// Runs `work` once a slot is free, earliest `copiedAt` first.
    ///
    /// Honors cancellation: a caller cancelled before it starts — including
    /// while parked in the queue — never runs `work` and gives back any slot
    /// it was handed. Nothing is retained past that point.
    public func run(copiedAt: Date, _ work: @Sendable () async -> Void) async {
        guard await acquire(copiedAt: copiedAt) else { return }
        await work()
        release()
    }

    /// How many are running right now. Test-facing; the value is a snapshot.
    public var inFlight: Int { running }

    /// How many are parked waiting for a slot. Test-facing.
    public var queueDepth: Int { waiting.count }

    /// Returns `true` when a slot is held and `work` should run.
    private func acquire(copiedAt: Date) async -> Bool {
        if Task.isCancelled { return false }
        guard running >= limit else {
            running += 1
            return true
        }

        let id = nextWaiterID
        nextWaiterID += 1
        let granted = await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
                waiting.append(Waiter(id: id, copiedAt: copiedAt, continuation: continuation))
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }

        // `false` means `cancelWaiter` pulled this one out of the queue, so no
        // slot was ever handed over and there is nothing to give back.
        guard granted else { return false }
        // Cancelled in the window between the hand-off and resuming here: the
        // slot IS held, so it has to go back or the scheduler leaks a permit.
        if Task.isCancelled {
            release()
            return false
        }
        return true
    }

    /// Removes a cancelled waiter and resumes it empty-handed. Whichever of
    /// this and ``release()`` reaches the waiter first removes it, so the
    /// continuation is resumed exactly once either way.
    private func cancelWaiter(_ id: UInt64) {
        guard let index = waiting.firstIndex(where: { $0.id == id }) else { return }
        waiting.remove(at: index).continuation.resume(returning: false)
    }

    private func release() {
        // Hand the slot straight to the next waiter rather than decrementing
        // and letting it re-check: that keeps the count honest under the
        // reentrancy that makes this actor work at all.
        guard let next = waiting.enumerated().min(by: { $0.element.copiedAt < $1.element.copiedAt })
        else {
            running -= 1
            return
        }
        waiting.remove(at: next.offset).continuation.resume(returning: true)
    }
}

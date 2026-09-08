/// Caps how many enrichments run at once.
///
/// Enrichment is dispatched per capture as an unstructured `Task`, and nothing
/// counted them. Capture is throttled — the macOS poll is 250 ms and coalesces
/// reads — but on-device inference takes seconds, so a burst of copies can
/// leave a growing pile of them in flight, each holding its own model session
/// and competing for the same Neural Engine. More at once does not finish the
/// pile sooner; it just makes every one of them slower and the memory higher.
///
/// FIFO on purpose: enrichment decorates a clip the user just copied, and the
/// one copied first is the one they are most likely to be looking for.
///
/// This bounds concurrency only. It does not retain the work, so a cancelled
/// caller simply never runs — the scheduler holds no reference to keep alive.
public actor EnrichmentScheduler {
    /// Two, not one: the stages within a single enrichment are serial (OCR,
    /// then title, then embedding), so a second slot keeps the engine busy
    /// while the first is between stages. Beyond that they mostly contend.
    public static let defaultLimit = 2

    private let limit: Int
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    public init(limit: Int = EnrichmentScheduler.defaultLimit) {
        self.limit = max(1, limit)
    }

    /// Runs `work` once a slot is free, in arrival order.
    public func run(_ work: @Sendable () async -> Void) async {
        await acquire()
        await work()
        release()
    }

    /// How many are running right now. Test-facing; the value is a snapshot.
    public var inFlight: Int { running }

    private func acquire() async {
        guard running >= limit else {
            running += 1
            return
        }
        await withCheckedContinuation { waiting.append($0) }
    }

    private func release() {
        // Hand the slot straight to the next waiter rather than decrementing
        // and letting it re-check: that keeps the count honest under the
        // reentrancy that makes this actor work at all.
        if waiting.isEmpty {
            running -= 1
        } else {
            waiting.removeFirst().resume()
        }
    }
}

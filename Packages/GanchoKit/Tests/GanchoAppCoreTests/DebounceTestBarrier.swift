/// Advance a synthetic debounce only after the entire expected burst arrives.
/// Even cancelled sleepers arrive: the coalescer checks cancellation after sleep.
actor DebounceTestBarrier {
    private var remaining: Int
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(arrivals: Int) { remaining = arrivals }

    func sleep() async {
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
            remaining -= 1
            if remaining <= 0 { release() }
        }
    }

    func release() {
        remaining = 0
        let pending = waiters
        waiters.removeAll()
        for waiter in pending { waiter.resume() }
    }
}

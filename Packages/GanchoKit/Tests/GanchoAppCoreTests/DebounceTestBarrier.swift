/// Advance a synthetic debounce only after the entire expected burst arrives.
/// Even cancelled sleepers arrive: the coalescer checks cancellation after sleep.
///
/// `arrivals` is therefore coupled to that detail. If the debounce ever checks
/// cancellation BEFORE sleeping, fewer sleepers arrive, `remaining` never
/// reaches zero and the waiters are never resumed — so every suite using this
/// barrier carries a `.timeLimit`, and a miscount fails instead of hanging.
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

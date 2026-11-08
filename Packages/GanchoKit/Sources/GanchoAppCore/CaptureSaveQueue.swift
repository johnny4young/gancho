/// Runs capture saves in order. A save that has not started when a pause
/// (Private Mode or a screen share) begins is dropped, like a read in flight.
@MainActor
public final class CaptureSaveQueue {
    private let pausesStarted: @MainActor () -> Int
    private var tail: Task<Void, Never>?

    public init(pausesStarted: @escaping @MainActor () -> Int) {
        self.pausesStarted = pausesStarted
    }

    /// `afterPrevious` makes this save wait for the one enqueued before it.
    @discardableResult
    public func enqueue(
        afterPrevious: Bool, _ save: @escaping @MainActor () async -> Void
    ) -> Task<Void, Never> {
        let previous = afterPrevious ? tail : nil
        let pausesStarted = pausesStarted
        let pausesAtEnqueue = pausesStarted()
        let task = Task { @MainActor in
            await previous?.value
            guard pausesStarted() == pausesAtEnqueue else { return }
            await save()
        }
        tail = task
        return task
    }
}

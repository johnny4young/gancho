import Observation

/// Copies a value derived from observable state to a consumer outside
/// Observation: once on `start()`, then each time an input changes. Equal
/// values are written once, so nothing runs while the state is at rest.
@MainActor
public final class ObservedValueMirror<Value: Equatable & Sendable> {
    private let read: @MainActor () -> Value
    private let write: @MainActor (Value) -> Void
    private var lastWritten: Value?
    /// Bumped by `start()` and `stop()`, so an older tracking never re-arms.
    private var generation = 0

    public init(
        read: @escaping @MainActor () -> Value,
        write: @escaping @MainActor (Value) -> Void
    ) {
        self.read = read
        self.write = write
    }

    public func start() {
        generation += 1
        follow(generation)
    }

    public func stop() {
        generation += 1
    }

    /// Re-reads for inputs Observation cannot see, such as a defaults key.
    public func refresh() {
        writeIfChanged(read())
    }

    private func follow(_ current: Int) {
        guard current == generation else { return }
        let value = withObservationTracking {
            read()
        } onChange: { [weak self] in
            // Fires before the change lands; read it on the next turn.
            Task { @MainActor in self?.follow(current) }
        }
        writeIfChanged(value)
    }

    private func writeIfChanged(_ value: Value) {
        guard lastWritten != value else { return }
        lastWritten = value
        write(value)
    }
}

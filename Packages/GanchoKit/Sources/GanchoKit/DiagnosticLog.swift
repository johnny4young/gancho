import Foundation

/// A small, capped, in-memory ring of recent operational issues — a durable
/// store that wouldn't open, a restore that failed, a sync that paused — for the
/// Privacy Center and support. It holds NO clip content: callers pass a category
/// and a short, content-free message. Process-lifetime only; never persisted,
/// never uploaded.
public final class DiagnosticLog: @unchecked Sendable {
    public struct Entry: Sendable, Equatable, Identifiable {
        public let id: UUID
        public let at: Date
        public let category: String
        public let message: String

        public init(id: UUID = UUID(), at: Date, category: String, message: String) {
            self.id = id
            self.at = at
            self.category = category
            self.message = message
        }
    }

    private let cap: Int
    private let lock = NSLock()
    private var buffer: [Entry] = []

    public init(cap: Int = 50) {
        self.cap = max(1, cap)
    }

    /// Append a content-free issue. Oldest entries fall off once `cap` is hit.
    public func record(_ category: String, _ message: String, at: Date = Date()) {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(Entry(at: at, category: category, message: message))
        if buffer.count > cap {
            buffer.removeFirst(buffer.count - cap)
        }
    }

    /// Most recent last (chronological).
    public var entries: [Entry] {
        lock.lock()
        defer { lock.unlock() }
        return buffer
    }

    public func clear() {
        lock.lock()
        defer { lock.unlock() }
        buffer.removeAll()
    }
}

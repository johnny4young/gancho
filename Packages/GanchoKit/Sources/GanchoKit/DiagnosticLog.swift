import Foundation
import Synchronization

/// A small, capped, in-memory ring of recent operational issues — a durable
/// store that wouldn't open, a restore that failed, a sync that paused — for the
/// Privacy Center and support. It holds NO clip content: callers pass a category
/// and a short, content-free message. Process-lifetime only; never persisted,
/// never uploaded.
public final class DiagnosticLog: Sendable {
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
    private let buffer: Mutex<[Entry]>

    public init(cap: Int = 50) {
        self.cap = max(1, cap)
        self.buffer = Mutex([])
    }

    /// Append a content-free issue. Oldest entries fall off once `cap` is hit.
    public func record(_ category: String, _ message: String, at: Date = Date()) {
        buffer.withLock { entries in
            entries.append(Entry(at: at, category: category, message: message))
            if entries.count > cap {
                entries.removeFirst(entries.count - cap)
            }
        }
    }

    /// Most recent last (chronological).
    public var entries: [Entry] {
        buffer.withLock { $0 }
    }

    public func clear() {
        buffer.withLock { $0.removeAll() }
    }
}

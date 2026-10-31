import Foundation
import GanchoKit

/// A secret's time left, for the peek's countdown and lifetime bar. The
/// deadline is the earlier of the stored expiry and the current lifetime
/// setting, because retention purges by capture time when it was shortened.
public struct SecretLifetime: Equatable, Sendable {
    public let start: Date
    public let deadline: Date

    /// Nil for a clip without a lifetime (not sensitive, or no expiry).
    public init?(item: ClipItem, lifetime: TimeInterval) {
        guard item.isSensitive, let expiresAt = item.expiresAt else { return nil }
        start = item.createdAt
        deadline = min(expiresAt, item.createdAt.addingTimeInterval(lifetime))
    }

    public func remaining(at now: Date) -> TimeInterval {
        max(0, deadline.timeIntervalSince(now))
    }

    /// Remaining share of the whole lifetime, 0...1.
    public func fraction(at now: Date) -> Double {
        let total = deadline.timeIntervalSince(start)
        guard total > 0 else { return 0 }
        return min(1, remaining(at: now) / total)
    }
}

/// The peek's timed reveal: plaintext shows for a fixed window, then masks again.
public struct SecretReveal: Equatable, Sendable {
    public static let window: TimeInterval = 10

    public private(set) var until: Date?

    public init() {}

    public func isRevealed(at now: Date) -> Bool {
        until.map { now < $0 } ?? false
    }

    public mutating func reveal(at now: Date) {
        until = now.addingTimeInterval(Self.window)
    }

    public mutating func hide() {
        until = nil
    }

    /// Reads a secret's text for a reveal. Nil, without touching the store,
    /// while revealing is not allowed; nil for content that is not text.
    public static func text(
        for item: ClipItem, allowed: Bool,
        loadContent: @Sendable (UUID) async throws -> ClipContent?
    ) async -> String? {
        guard allowed else { return nil }
        let payload = await ClipPreviewLoader().load(
            item, revealMaskedContent: true, loadContent: loadContent)
        switch payload {
        case .text(let text): return text
        case .fileReferences(let paths): return paths.joined(separator: "\n")
        case .masked, .binary, .unavailable: return nil
        }
    }
}

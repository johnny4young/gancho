import Foundation
import GanchoKit

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

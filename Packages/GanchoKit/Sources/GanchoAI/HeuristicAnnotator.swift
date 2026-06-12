import Foundation
import GanchoKit

/// Deterministic annotation fallback: runs on EVERY device, zero network,
/// no Apple Intelligence required. This is the `.unavailable` path — when
/// Foundation Models is missing (old hardware, AI disabled in Settings,
/// other platforms), titles degrade gracefully instead of disappearing.
public struct HeuristicAnnotator: ClipAnnotating {
    private let classifier = RuleClassifier()

    public init() {}

    public func annotate(_ text: String) async throws -> ClipAnnotation {
        let kind = classifier.classify(text)
        return ClipAnnotation(title: Self.title(for: text, kind: kind), kind: kind)
    }

    /// Titles are derived per kind so they stay specific without a model:
    /// URLs show their host + leading path, identifiers name their format,
    /// and free text falls back to its first line, clamped.
    static func title(for text: String, kind: ClipContentKind) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch kind {
        case .url:
            if let url = URL(string: trimmed), let host = url.host() {
                let path = url.path()
                let lead = path.split(separator: "/").first.map { "/\($0)" } ?? ""
                return host + lead
            }
            return clampedFirstLine(trimmed)
        case .email, .phoneNumber, .color, .uuid:
            return clampedFirstLine(trimmed)
        case .jwt:
            return "JWT token"
        case .json:
            return "JSON · " + clampedFirstLine(trimmed, limit: 36)
        case .creditCard:
            // Never surface digits in a title.
            return "Card number"
        case .secret:
            // Never surface secret material in a title.
            return "Secret"
        default:
            return clampedFirstLine(trimmed)
        }
    }

    /// First non-empty line, word-clamped (≤6 words) and length-clamped so
    /// titles match what the model-backed annotator is instructed to emit.
    static func clampedFirstLine(_ text: String, limit: Int = 48) -> String {
        let firstLine =
            text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .first.map(String.init) ?? text
        let words = firstLine.split(separator: " ", omittingEmptySubsequences: true)
        var title = words.prefix(6).joined(separator: " ")
        if title.count > limit {
            title = String(title.prefix(limit)).trimmingCharacters(in: .whitespaces) + "…"
        }
        return title
    }
}

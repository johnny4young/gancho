import Foundation
import GanchoKit

/// Tier-1 enrichment for a clip: a human-friendly title plus the model's
/// (or heuristic's) view of what the content is. Enrichment is additive —
/// the tier-0 `RuleClassifier` verdict already shipped with the capture,
/// so a failed or slow annotation never blocks core UX.
public struct ClipAnnotation: Sendable, Equatable {
    public var title: String
    public var kind: ClipContentKind

    public init(title: String, kind: ClipContentKind) {
        self.title = title
        self.kind = kind
    }
}

/// Boundary for clip annotation backends.
///
/// Designed as Gancho's own seam on purpose: WWDC26 announced a unified
/// `LanguageModel` protocol (on-device / Private Cloud Compute / external
/// models behind one API), but it is not in the macOS 26 stable SDK. When it
/// ships, it becomes one more implementation behind this protocol — callers
/// never change.
public protocol ClipAnnotating: Sendable {
    /// Annotates clip text. Implementations must enforce their own input
    /// budget (Foundation Models shares a 4,096-token window across input
    /// AND output) and throw rather than block when a backend is unavailable.
    func annotate(_ text: String) async throws -> ClipAnnotation
}

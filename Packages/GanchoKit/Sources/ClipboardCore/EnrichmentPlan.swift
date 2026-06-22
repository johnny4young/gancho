import Foundation
import GanchoKit

/// One asynchronous enrichment pass a freshly captured clip can flow through
/// AFTER the synchronous tier-0 classifier has already run. Each case maps to a
/// real on-device stage; the deterministic classifier is not represented here
/// because it runs inline at capture and is never gated.
public enum EnrichmentStage: Sendable, Equatable, CaseIterable {
    /// Tier 1 — Apple Intelligence writes a short, specific title (text clips).
    case title
    /// On-device sentence embedding indexes the clip for semantic search.
    case embedding
    /// On-device OCR extracts the words inside an image clip for full-text search.
    case ocr
}

/// What kind of payload an enrichment plan is being computed for. Kept separate
/// from `ClipContent` so the gating policy is a pure value type the tests can
/// drive without constructing store payloads.
public enum EnrichableContent: Sendable, Equatable {
    /// A text-bearing clip. `hasTitle` skips the title stage when one already
    /// rode in with the capture (e.g. a clip synced from another device).
    case text(hasTitle: Bool)
    /// An image clip — the only payload OCR runs on.
    case image
    /// Anything with no enrichable payload (file references, non-image binary).
    case other
}

/// Decides which enrichment stages run for one captured clip given the device
/// tier and the user's Intelligence toggles. The policy is pure and shared by
/// every platform's capture pipeline so the two never drift — the IO each stage
/// performs (calling the annotator, embedder, or OCR and writing the result
/// back to the store) lives in the app layer that owns the store.
///
/// Two invariants the type enforces, ahead of any toggle:
/// - Enrichment is a Pro capability (`isPro`); the free tier plans nothing.
/// - A sensitive clip is never enriched — gancho does not title, index, or OCR
///   a secret. The veto wins over every per-stage toggle.
public struct EnrichmentPlan: Sendable, Equatable {
    /// The stages to run, in no particular order (each is independent).
    public let stages: Set<EnrichmentStage>

    /// True when nothing is planned — the caller can skip opening the store.
    public var isEmpty: Bool { stages.isEmpty }

    /// Whether a given stage is part of this plan.
    public func runs(_ stage: EnrichmentStage) -> Bool { stages.contains(stage) }

    /// - Parameters:
    ///   - content: the enrichable payload category.
    ///   - isSensitive: a sensitive clip plans nothing (veto over every toggle).
    ///   - isPro: enrichment is a Pro capability; the free tier plans nothing.
    ///   - preferences: the per-stage Intelligence toggles.
    public init(
        content: EnrichableContent,
        isSensitive: Bool,
        isPro: Bool,
        preferences: IntelligencePreferences
    ) {
        guard isPro, !isSensitive else {
            stages = []
            return
        }
        var planned: Set<EnrichmentStage> = []
        switch content {
        case .text(let hasTitle):
            if preferences.intelligentTitles, !hasTitle { planned.insert(.title) }
            if preferences.semanticSearch { planned.insert(.embedding) }
        case .image:
            if preferences.searchableScreenshots { planned.insert(.ocr) }
        case .other:
            break
        }
        stages = planned
    }

    /// Convenience that derives the payload category from a stored `ClipContent`
    /// plus the clip's classified kind, mirroring each capture pipeline's
    /// content switch exactly: image binary → OCR, text → title/embedding,
    /// everything else (file references, RTF binary) → nothing.
    public init(
        content: ClipContent?,
        kind: ClipContentKind,
        isSensitive: Bool,
        hasTitle: Bool,
        isPro: Bool,
        preferences: IntelligencePreferences
    ) {
        let category: EnrichableContent
        switch content {
        case .binary where kind == .image:
            category = .image
        case .text:
            category = .text(hasTitle: hasTitle)
        default:
            category = .other
        }
        self.init(
            content: category, isSensitive: isSensitive, isPro: isPro, preferences: preferences)
    }
}

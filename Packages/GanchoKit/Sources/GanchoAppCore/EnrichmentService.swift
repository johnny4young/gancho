import ClipboardCore
import Foundation
import GanchoAI
import GanchoKit

/// Runs a captured clip's on-device enrichment IO — OCR, Apple Intelligence
/// titles, and semantic embeddings — the single home for the pipeline both app
/// shells used to inline (`AppModel`/`IOSAppModel.enrich`). The `EnrichmentPlan`
/// gating that decides WHICH stages run stays in the capture pipeline; this type
/// only performs the IO each planned stage implies and writes it back through the
/// `ClipEnriching` facet.
///
/// The two shells had diverged in exactly two places, both parameterized here so
/// this is a behavior-preserving move, not a merge:
/// - Whether a title is written: iOS runs it on `plan.runs(.title)`; macOS also
///   runs it for the free "AI title taste". The caller passes that decision as
///   `writeTitle`.
/// - What happens right after a title write: iOS refreshes with `search()`; macOS
///   consumes a free-taste credit (and nudges when it hits zero) then
///   `refreshRecents()`. The caller passes that as `onTitleWritten`, which runs on
///   the caller's actor immediately after the write, in the original position.
///
/// Stateless and `Sendable`: it constructs `ImageTextExtractor` /
/// `TieredClipAnnotator` / `ContextualSentenceEmbedder` per call exactly as the
/// inlined code did (the process-lifetime-instance optimization is deliberately
/// NOT taken here — this is a pure move). Each per-call helper is created and
/// consumed inside its own `if` with no `await` between construction and last
/// use, so no non-`Sendable` value crosses an actor boundary and the type needs no
/// `@MainActor` isolation. On CI the annotator degrades to the heuristic and the
/// embedder reports `hasAvailableAssets == false`, so those stages yield nothing
/// there; the plan/`writeTitle` gating remains unit-testable.
public struct EnrichmentService: Sendable {
    public init() {}

    /// Runs the enrichment IO shared by both shells, in the SAME order as the
    /// inlined code: OCR → title → embedding.
    ///
    /// - Parameters:
    ///   - item: the freshly captured clip to enrich.
    ///   - content: its stored payload (image binary for OCR, text otherwise).
    ///   - plan: the shared gating policy; drives the OCR and embedding stages.
    ///   - writeTitle: the platform's decision to write a title (iOS:
    ///     `plan.runs(.title)`; macOS: `plan.runs(.title) || tasteTitle`).
    ///   - store: the enrichment write surface.
    ///   - onTitleWritten: runs immediately after a successful title write, on
    ///     the caller's actor, so each shell keeps its own refresh and the macOS
    ///     free-taste bookkeeping in the exact original position.
    public func enrich(
        _ item: ClipItem, content: ClipContent?, plan: EnrichmentPlan,
        writeTitle: Bool, store: any ClipEnriching,
        onTitleWritten: @Sendable () async -> Void
    ) async {
        // Searchable screenshots (OCR).
        if plan.runs(.ocr), case .binary(let data, _)? = content,
            let text = try? await ImageTextExtractor().extractText(from: data)
        {
            _ = try? await store.attachExtractedText(id: item.id, text: text)
        }
        // Tier 1 — Apple Intelligence titles.
        if writeTitle, case .text(let text)? = content,
            let annotation = try? await TieredClipAnnotator().annotate(text)
        {
            let wroteTitle =
                (try? await store.updateTitleIfEmpty(id: item.id, title: annotation.title)) == true
            if wroteTitle { await onTitleWritten() }
        }
        // Semantic vector (the embedder caches its model after the first call).
        if plan.runs(.embedding), case .text(let text)? = content,
            let embedder = ContextualSentenceEmbedder(), embedder.hasAvailableAssets,
            let vector = try? embedder.vector(for: String(text.prefix(1_000)))
        {
            _ = try? await store.saveEmbedding(clipID: item.id, vector: vector)
        }
    }
}

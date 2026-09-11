import Foundation
import GanchoAI
import GanchoKit

/// One entry point for the on-device intelligence a clip shell offers: Smart
/// Paste, ask-your-clipboard, and board suggestion.
///
/// Exists because these three had already drifted once. macOS hand-rolled its
/// own retrieval for ask-your-clipboard until it was unified onto
/// ``ClipboardQA``, and even after that its availability check still read
/// `ClipboardQAService` — the type `ClipboardQA` wraps — so "can I ask?" and
/// "who answers?" were reported by different layers. They agree today only
/// because one forwards to the other, which is exactly the kind of agreement
/// that stops holding the moment either side grows a condition.
///
/// Stateless and `Sendable`, like the coordinators it fronts —
/// ``BoardSuggestionService``, ``ClipboardQA`` and `SmartPasteService` are all
/// `Sendable` value types. There is no actor-isolated state here to protect, so
/// `@MainActor` would only narrow who may call it: both shells are on the main
/// actor today, but nothing in this package requires that of a caller. The
/// store handle and the user's toggles are passed per call rather than
/// captured, so a facade can never answer from a store the shell has since
/// replaced or a preference the user has since changed.
///
/// What stays in the shells is presentation: each maps a ``ClipboardQA``
/// outcome to its own localized answer copy, because those strings live in the
/// per-app catalogs and a package has no business owning them.
public struct ClipIntelligenceFacade: Sendable {
    private let smartPasteService = SmartPasteService()

    public init() {}

    /// Apple Intelligence is present and usable for model-backed rewrites and
    /// translations. The user's Smart Paste opt-in is a SEPARATE gate the shell
    /// applies — deterministic actions such as PII redaction need no model, so
    /// availability must not hide the whole menu.
    public static var modelAvailable: Bool { SmartPasteService.isAvailable }

    /// Whether ask-your-clipboard can answer at all. Read from ``ClipboardQA``,
    /// the type that actually answers, so the two can never disagree.
    public static var askAvailable: Bool { ClipboardQA.isAvailable }

    /// Transforms a clip's text on-device; nil if unavailable or the model
    /// declined. Pure enrichment — never fails the caller.
    public func transform(_ text: String, action: SmartPasteAction) async -> String? {
        try? await smartPasteService.transform(text, action: action)
    }

    /// On-device translation to `target` — Apple's native Translation session
    /// when the pair is installed, the on-device model otherwise; nil on failure.
    public func translate(_ text: String, to target: Locale.Language) async -> String? {
        try? await smartPasteService.translate(text, to: target)
    }

    /// Retrieves the most relevant clips (semantic when the embeddings are
    /// ready, else full-text) and has the on-device model answer grounded ONLY
    /// in them. Retrieval and the sensitive-clip filter live in ``ClipboardQA``,
    /// not here — this only routes.
    ///
    /// Returns `.unavailable` when there is no durable store, which is the same
    /// answer the shells already gave for that case and the same one the model
    /// gives when it cannot run.
    public func ask(
        _ question: String, store: (any ClipReading & ClipSearching)?, useSemantic: Bool
    ) async -> ClipboardQA.Outcome {
        guard let store else { return .unavailable }
        return await ClipboardQA().answer(
            question: question, store: store, useSemantic: useSemantic)
    }

    /// Suggests the board this clip probably belongs to, by a semantic k-NN vote
    /// over how similar clips were filed. Only ever suggests; nil when the
    /// toggle is off, the clip is sensitive, there is no durable store, there
    /// are no eligible user boards, or the neighborhood shows no clear home.
    /// 100% on-device.
    ///
    /// The sensitive check is DOUBLED on purpose: `BoardSuggestionService`
    /// already refuses a sensitive clip as its first line, and this repeats it.
    /// Defence in depth for a privacy rule is worth one redundant `guard` — but
    /// it does mean the authoritative test for that behavior is the suggester's
    /// own, not this type's, since a test here cannot tell which guard fired.
    public func suggestedBoard(
        for item: ClipItem,
        store: (any BoardStoring & ClipReading & ClipSearching)?,
        autoBoardEnabled: Bool
    ) async -> Pinboard? {
        guard autoBoardEnabled, !item.isSensitive, let store else { return nil }
        return await BoardSuggestionService().suggest(for: item, store: store)
    }
}

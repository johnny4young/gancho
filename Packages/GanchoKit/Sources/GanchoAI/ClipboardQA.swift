import Foundation
import GanchoKit

/// "Ask your clipboard" end to end: retrieve the most relevant clips (semantic
/// when the embeddings are ready, else full-text), drop anything sensitive, and
/// have the on-device model answer grounded ONLY in them. The single source of
/// truth shared by the iOS app's ask UI and the Shortcuts `AskClipboardIntent`
/// — neither forks the retrieval or the privacy filtering.
public struct ClipboardQA: Sendable {
    public enum Outcome: Sendable, Equatable {
        /// The on-device model isn't available, or the question was empty.
        case unavailable
        /// Nothing relevant (and non-sensitive) to ground an answer in.
        case noMatch
        /// Clips were retrieved but the model couldn't produce an answer.
        case failed([ClipItem])
        /// A grounded answer plus the clips it was grounded in.
        case answered(String, [ClipItem])
    }

    public init() {}

    public static var isAvailable: Bool { ClipboardQAService.isAvailable }

    /// The grounding set for a question: semantic hits when embeddings are ready,
    /// else FTS, with sensitive clips removed. Pure retrieval (no model), so the
    /// "never ground on a secret" contract is unit-testable on its own.
    public static func retrieve(
        question: String, store: GRDBClipboardStore, useSemantic: Bool
    ) async -> [ClipItem] {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        // Filter sensitive WITHIN each strategy: a semantic pass that returns
        // only secrets must still fall through to FTS, or the user gets a false
        // "no match" while non-sensitive full-text hits exist.
        var clips: [ClipItem] = []
        if useSemantic, let embedder = ContextualSentenceEmbedder(), embedder.hasAvailableAssets,
            let vector = try? embedder.vector(for: String(trimmed.prefix(1_000)))
        {
            clips = ((try? await store.semanticSearch(queryVector: vector, topK: 6)) ?? [])
                .filter { !$0.isSensitive }
        }
        if clips.isEmpty {
            clips = ((try? await store.search(ClipSearchQuery(text: trimmed), limit: 6)) ?? [])
                .filter { !$0.isSensitive }
        }
        return clips
    }

    private let service = ClipboardQAService()

    /// Retrieve, ground, and answer. The caller maps `Outcome` to its own
    /// localized copy (the app's answer card, the intent's dialog).
    public func answer(
        question: String, store: GRDBClipboardStore, useSemantic: Bool
    ) async -> Outcome {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard Self.isAvailable, !trimmed.isEmpty else { return .unavailable }

        let safe = await Self.retrieve(question: trimmed, store: store, useSemantic: useSemantic)
        guard !safe.isEmpty else { return .noMatch }

        var sources: [String] = []
        for clip in safe {
            let body: String
            if case .text(let text)? = try? await store.content(for: clip.id) {
                body = text
            } else {
                body = clip.preview
            }
            sources.append(clip.title.isEmpty ? body : "\(clip.title): \(body)")
        }
        guard let answer = try? await service.answer(question: trimmed, sources: sources) else {
            return .failed(safe)
        }
        return .answered(answer, safe)
    }
}

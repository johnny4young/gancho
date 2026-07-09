import Foundation
import FoundationModels
import GanchoKit

/// Errors the tier-1 annotator can surface to the tiered fallback chain.
public enum AnnotationError: Error, Equatable {
    /// Apple Intelligence is unavailable on this device (unsupported
    /// hardware, disabled in Settings, model assets not ready).
    case backendUnavailable
}

/// The structured output contract for the on-device model. `@Generable`
/// guarantees the response parses into this shape — no JSON scraping.
@Generable
private struct AnnotationDraft {
    @Guide(description: "Short, specific title for the snippet. At most six words. No quotes.")
    var title: String

    @Guide(
        description:
            // swiftlint:disable:next line_length
            "Best matching category: text, url, email, phoneNumber, color, jwt, json, uuid, code, creditCard, or secret."
    )
    var category: String
}

/// Tier-1 annotator backed by the on-device Foundation Models system model.
///
/// Context budget: the system model shares a 4,096-token window across input
/// AND output (`SystemLanguageModel.default.contextSize`, verified 26.5).
/// Input is clamped to `maxPromptCharacters` (≈400–700 tokens for typical
/// clips) and each clip gets a FRESH session: reusing one session would let
/// the transcript accumulate until the window overflows mid-batch.
public struct FoundationModelAnnotator: ClipAnnotating {
    /// Cheap availability gate callers can use to pick a tier up front.
    public static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    private let maxPromptCharacters: Int

    private static let instructions = """
        You title and categorize clipboard snippets. Reply with a title of at \
        most six words that says what the snippet IS (not what it contains \
        verbatim), and the best matching category. Never include passwords, \
        card numbers, or secret material in the title.
        """

    public init(maxPromptCharacters: Int = 1500) {
        self.maxPromptCharacters = maxPromptCharacters
    }

    public func annotate(_ text: String) async throws -> ClipAnnotation {
        guard Self.isAvailable else { throw AnnotationError.backendUnavailable }

        let clipped = String(text.prefix(maxPromptCharacters))
        let session = LanguageModelSession(instructions: Self.instructions)
        let response = try await session.respond(
            to: clipped, generating: AnnotationDraft.self)

        return ClipAnnotation(
            title: HeuristicAnnotator.clampedFirstLine(response.content.title),
            kind: ClipContentKind(rawValue: response.content.category) ?? .text)
    }
}

/// Primary/fallback composition: try the model, degrade to deterministic
/// heuristics on ANY failure (unavailable, guardrail refusal, context
/// overflow). Annotation is enrichment — it must never fail the pipeline.
public struct TieredClipAnnotator: ClipAnnotating {
    private let primary: any ClipAnnotating
    private let fallback: any ClipAnnotating

    public init(
        primary: any ClipAnnotating = FoundationModelAnnotator(),
        fallback: any ClipAnnotating = HeuristicAnnotator()
    ) {
        self.primary = primary
        self.fallback = fallback
    }

    public func annotate(_ text: String) async throws -> ClipAnnotation {
        do {
            return try await primary.annotate(text)
        } catch {
            return try await fallback.annotate(text)
        }
    }
}

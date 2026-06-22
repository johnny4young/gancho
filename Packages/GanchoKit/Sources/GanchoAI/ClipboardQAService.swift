import Foundation
import FoundationModels

/// "Ask your clipboard": answer a natural-language question grounded ONLY in
/// the clips the caller retrieved (semantic search up front). On-device via the
/// system model — the question and the clip text never leave the device.
///
/// Privacy: the caller filters sensitive clips out of the context, and the
/// instructions forbid revealing secret material even if some slips through.
/// The model is told to answer ONLY from the provided items and to admit when
/// the answer isn't there — no hallucinated facts about the user's data.
public struct ClipboardQAService: Sendable {
    public static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    private let maxSourceCharacters: Int
    private let maxSources: Int

    public init(maxSourceCharacters: Int = 600, maxSources: Int = 6) {
        self.maxSourceCharacters = maxSourceCharacters
        self.maxSources = maxSources
    }

    public static let instructions = """
        You answer the user's question using ONLY the clipboard items provided as \
        context. If the answer is not in them, say you couldn't find it in the \
        clipboard history — never guess or invent. Be concise (one or two \
        sentences) and refer to an item by its number when useful. Never reveal \
        passwords, card numbers, API keys, or other secret material.
        """

    /// Pure prompt builder (numbered context + the question) — unit-tested.
    public static func prompt(question: String, sources: [String]) -> String {
        var lines = ["Clipboard items:"]
        for (index, source) in sources.enumerated() {
            lines.append("[\(index + 1)] \(source)")
        }
        lines.append("")
        lines.append("Question: \(question)")
        return lines.joined(separator: "\n")
    }

    /// Answers grounded in `sources` (already retrieved + sensitive-filtered by
    /// the caller). Throws `backendUnavailable` when Apple Intelligence is off.
    public func answer(question: String, sources: [String]) async throws -> String {
        guard Self.isAvailable else { throw AnnotationError.backendUnavailable }
        let clipped = sources.prefix(maxSources).map { String($0.prefix(maxSourceCharacters)) }
        let session = LanguageModelSession(instructions: Self.instructions)
        let response = try await session.respond(
            to: Self.prompt(question: question, sources: Array(clipped)))
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

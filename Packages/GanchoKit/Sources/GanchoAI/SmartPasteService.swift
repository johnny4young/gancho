import Foundation
import FoundationModels

/// On-device "Smart paste": rewrite a clip with Apple Intelligence before
/// pasting — summarize, fix grammar, change tone, or pull key points. Same
/// backend as the title annotator (`SystemLanguageModel`), so it is fully
/// on-device (zero network) and degrades the same way: when Apple Intelligence
/// is unavailable the caller hides the affordance.
///
/// Privacy: the prompt text never leaves the device, and every action's
/// instructions forbid echoing secret material. Callers additionally gate the
/// feature off for sensitive clips, so a masked secret is never sent to the
/// model in the first place.
public enum SmartPasteAction: String, CaseIterable, Sendable, Identifiable {
    case summarize
    case proofread
    case formal
    case friendly
    case keyPoints
    case redactPII

    public var id: String { rawValue }

    /// User-facing label — fed through the String Catalog by the UI.
    public var titleKey: String {
        switch self {
        case .summarize: "Summarize"
        case .proofread: "Fix grammar"
        case .formal: "Make formal"
        case .friendly: "Make friendly"
        case .keyPoints: "Key points"
        case .redactPII: "Redact PII"
        }
    }

    public var symbolName: String {
        switch self {
        case .summarize: "text.line.first.and.arrowtriangle.forward"
        case .proofread: "checkmark.circle"
        case .formal: "briefcase"
        case .friendly: "face.smiling"
        case .keyPoints: "list.bullet"
        case .redactPII: "eye.slash"
        }
    }

    /// The on-device model's system instructions for this action. Pure (no I/O)
    /// so it is unit-tested directly. Always forbids leaking secret material.
    public var instructions: String {
        let guardrail =
            " Never include passwords, card numbers, API keys, or other secret material."
        switch self {
        case .summarize:
            return
                "Summarize the user's text in one to three clear sentences. Stay faithful to the meaning. Output only the summary, nothing else."
                + guardrail
        case .proofread:
            return
                "Correct the spelling, grammar, and punctuation of the user's text. Preserve its meaning, tone, and line breaks. Output only the corrected text, nothing else."
                + guardrail
        case .formal:
            return
                "Rewrite the user's text in a clear, professional, formal tone. Preserve its meaning. Output only the rewritten text, nothing else."
                + guardrail
        case .friendly:
            return
                "Rewrite the user's text in a warm, friendly, conversational tone. Preserve its meaning. Output only the rewritten text, nothing else."
                + guardrail
        case .keyPoints:
            return
                "Extract the key points from the user's text as a short bullet list, one point per line beginning with \"- \". Output only the list, nothing else."
                + guardrail
        case .redactPII:
            // Primary path is the deterministic `PIIRedactor`; these instructions
            // describe the same intent and exist as a model fallback.
            return
                "Rewrite the user's text with every piece of personally identifiable information — names, emails, phone numbers, postal addresses, and account or ID numbers — replaced by a bracketed placeholder such as [name] or [email]. Preserve everything else exactly. Output only the redacted text, nothing else."
                + guardrail
        }
    }
}

public struct SmartPasteService: Sendable {
    /// Cheap availability gate the UI uses to show/hide the affordance.
    public static var isAvailable: Bool {
        SystemLanguageModel.default.availability == .available
    }

    /// Input is clamped so prompt + completion fit the system model's shared
    /// context window (it rewrites text, so the output can be as long as the
    /// input — leave room for both).
    private let maxPromptCharacters: Int

    public init(maxPromptCharacters: Int = 3000) {
        self.maxPromptCharacters = maxPromptCharacters
    }

    /// Translation instructions for a target language (pure → unit-tested).
    /// `language` is an English language name (e.g. "Spanish") so the on-device
    /// model has an unambiguous target.
    public static func translateInstructions(to language: String) -> String {
        "Translate the user's text into \(language). Preserve its meaning, tone, and line breaks. Output only the translation, nothing else. Never include passwords, card numbers, API keys, or other secret material."
    }

    /// On-device translation (via the same system model). Kept separate from
    /// `SmartPasteAction` because it carries a target language.
    public func translate(_ text: String, to language: String) async throws -> String {
        guard Self.isAvailable else { throw AnnotationError.backendUnavailable }
        let clipped = String(text.prefix(maxPromptCharacters))
        let session = LanguageModelSession(instructions: Self.translateInstructions(to: language))
        let response = try await session.respond(to: clipped)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Runs the action on a FRESH session (no transcript carryover) and returns
    /// the transformed text. Throws `AnnotationError.backendUnavailable` when
    /// Apple Intelligence is off — enrichment, never a hard failure for callers.
    public func transform(_ text: String, action: SmartPasteAction) async throws -> String {
        // Redaction is deterministic and on-device: it must preserve the text
        // exactly except for PII, and must not depend on the model running.
        if action == .redactPII { return PIIRedactor.redact(text) }
        guard Self.isAvailable else { throw AnnotationError.backendUnavailable }
        let clipped = String(text.prefix(maxPromptCharacters))
        let session = LanguageModelSession(instructions: action.instructions)
        let response = try await session.respond(to: clipped)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

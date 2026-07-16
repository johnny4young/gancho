import Foundation
import FoundationModels

/// On-device "Smart paste": rewrite a clip with Apple Intelligence before
/// pasting — summarize, fix grammar, change tone, or pull key points — plus a
/// deterministic PII-redaction action. Model-backed actions use the same
/// backend as the title annotator (`SystemLanguageModel`), so they are fully
/// on-device (zero network) and degrade the same way; redaction stays available
/// without model assets.
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

    /// The on-device model's system instructions for this action — owned by
    /// `PromptCatalog` (frozen wording + version + evaluation). Pure (no I/O)
    /// so it is unit-tested directly. Always forbids leaking secret material.
    public var instructions: String {
        PromptCatalog.smartPaste(self).instructions
    }
}

public struct SmartPasteService: Sendable {
    /// Cheap availability gate the UI uses for model-backed rewrites and
    /// translations. Deterministic PII redaction does not require this to be
    /// true.
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
    /// model has an unambiguous target. Wording owned by `PromptCatalog`.
    public static func translateInstructions(to language: String) -> String {
        PromptCatalog.translateInstructions(to: language)
    }

    /// On-device translation (via the same system model). Kept separate from
    /// `SmartPasteAction` because it carries a target language.
    public func translate(_ text: String, to language: String) async throws -> String {
        guard Self.isAvailable else { throw AnnotationError.backendUnavailable }
        // Structural secret redaction BEFORE the model sees the text — the
        // live evaluation proved instructions alone don't stop echo.
        let safe = ModelInputSanitizer.sanitized(text)
        let clipped = String(safe.prefix(maxPromptCharacters))
        let session = LanguageModelSession(instructions: Self.translateInstructions(to: language))
        let response = try await session.respond(to: clipped)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Runs the action on a FRESH session (no transcript carryover) and returns
    /// the transformed text. Model-backed actions throw
    /// `AnnotationError.backendUnavailable` when Apple Intelligence is off;
    /// `.redactPII` is deterministic and does not require model availability.
    public func transform(_ text: String, action: SmartPasteAction) async throws -> String {
        // Redaction is deterministic and on-device: it must preserve the text
        // exactly except for PII, and must not depend on the model running.
        if action == .redactPII { return PIIRedactor.redact(text) }
        guard Self.isAvailable else { throw AnnotationError.backendUnavailable }
        // Structural secret redaction BEFORE the model sees the text — a
        // "faithful" summary of a memo with a key line would otherwise carry
        // the key into pasted output (caught live by the prompt evaluation).
        let safe = ModelInputSanitizer.sanitized(text)
        let clipped = String(safe.prefix(maxPromptCharacters))
        let session = LanguageModelSession(instructions: action.instructions)
        let response = try await session.respond(to: clipped)
        return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

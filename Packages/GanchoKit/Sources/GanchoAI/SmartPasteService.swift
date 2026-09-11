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
    /// true. Below macOS/iOS 26 the Foundation Models tier does not exist, so
    /// this is `false` there — the same degradation the UI already shows when
    /// Apple Intelligence is switched off.
    public static var isAvailable: Bool {
        guard #available(macOS 26.0, iOS 26.0, *) else { return false }
        return SystemLanguageModel.default.availability == .available
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

    /// On-device translation to `target`. Kept separate from `SmartPasteAction`
    /// because it carries a target language.
    ///
    /// Prefers Apple's native Translation session when the language pair is
    /// already installed — a purpose-built engine that outruns prompting the
    /// model once warm, though a first short translation can pay a cold start —
    /// and falls back to the on-device model otherwise (see
    /// ``TranslationRoute/route(for:)`` for why a downloadable pair does too).
    ///
    /// Secret redaction runs BEFORE either engine sees the text. The live
    /// evaluation proved instructions alone don't stop a model echoing a secret,
    /// and redacting only ahead of the model would hand the native route the
    /// unredacted original — the two routes must agree on what leaves this call.
    ///
    /// Cancellation is rethrown, never retried: a request the user abandoned must
    /// not quietly start the second, slower engine.
    public func translate(
        _ text: String, to target: Locale.Language, engines: TranslationEngines = .live
    ) async throws -> String {
        let safe = ModelInputSanitizer.sanitized(text)
        let clipped = String(safe.prefix(maxPromptCharacters))

        if let source = engines.identifySource(clipped),
            TranslationRoute.route(for: await engines.pairStatus(source, target)) == .native
        {
            do {
                return try await engines.native(clipped, source, target)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                if error is CancellationError || Task.isCancelled { throw error }
                // Any other native failure (a pair uninstalled since the check,
                // an unsupported combination) takes the model path below.
            }
        }
        return try await engines.languageModel(clipped, Self.englishLanguageName(for: target))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The English name of `language` — what the model fallback's prompt needs
    /// for an unambiguous target (e.g. "Spanish" for `es`).
    static func englishLanguageName(for language: Locale.Language) -> String {
        let code = language.languageCode?.identifier ?? language.minimalIdentifier
        return Locale(identifier: "en").localizedString(forLanguageCode: code) ?? code
    }

    /// Runs the action on a FRESH session (no transcript carryover) and returns
    /// the transformed text. Model-backed actions throw
    /// `AnnotationError.backendUnavailable` when Apple Intelligence is off;
    /// `.redactPII` is deterministic and does not require model availability.
    public func transform(_ text: String, action: SmartPasteAction) async throws -> String {
        // Redaction is deterministic and on-device: it must preserve the text
        // exactly except for PII, and must not depend on the model running.
        if action == .redactPII { return PIIRedactor.redact(text) }
        guard #available(macOS 26.0, iOS 26.0, *), Self.isAvailable else {
            throw AnnotationError.backendUnavailable
        }
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

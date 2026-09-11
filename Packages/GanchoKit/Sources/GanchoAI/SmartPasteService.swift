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
    /// Cancellation is checked before each engine starts and again when it
    /// answers, and a `CancellationError` an engine throws is rethrown, never
    /// retried. An abandoned request therefore starts no engine, even when it was
    /// cancelled during the availability query, which cannot throw; never falls
    /// back to the second, slower engine; and throws `CancellationError` rather
    /// than delivering an answer that arrives after it was abandoned.
    public func translate(
        _ text: String, to target: Locale.Language, engines: TranslationEngines = .live
    ) async throws -> String {
        let safe = ModelInputSanitizer.sanitized(text)
        let clipped = String(safe.prefix(maxPromptCharacters))

        if let source = engines.identifySource(clipped),
            TranslationRoute.route(for: await engines.pairStatus(source, target)) == .native
        {
            do {
                return try await Self.answer { try await engines.native(clipped, source, target) }
            } catch let cancellation as CancellationError {
                throw cancellation
            } catch {
                // Any other native failure (a pair uninstalled since the check,
                // an unsupported combination) takes the model path below, whose
                // own cancellation check keeps an abandoned request from starting it.
            }
        }
        return try await Self.answer {
            try await engines.languageModel(clipped, Self.englishLanguageName(for: target))
        }
    }

    /// Runs one engine for a request that is still wanted, trimming its answer.
    ///
    /// The check before it starts is the only place a cancellation during
    /// `pairStatus` can surface, since that query cannot throw. The check after
    /// it answers discards a result nobody is waiting for.
    private static func answer(from engine: () async throws -> String) async throws -> String {
        try Task.checkCancellation()
        let result = try await engine()
        try Task.checkCancellation()
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// The English name the model fallback's prompt needs for an unambiguous
    /// target: "Spanish" for `es`.
    ///
    /// Named from the MINIMAL identifier rather than the bare language code, so
    /// a script or region that changes the answer survives into the prompt:
    /// `zh-Hant` minimizes to `zh-TW`, "Chinese (Taiwan)", and `pt-PT` stays
    /// "Portuguese (Portugal)". A subtag that is already the language's default
    /// folds away (`pt-BR` minimizes to `pt`), exactly as CLDR's likely-subtags
    /// data treats it, which also keeps every base code the app offers on the
    /// plain name its prompt always used.
    static func englishLanguageName(for language: Locale.Language) -> String {
        let identifier = language.minimalIdentifier
        return Locale(identifier: "en").localizedString(forIdentifier: identifier) ?? identifier
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

import Foundation
import FoundationModels
import NaturalLanguage
import Translation

/// What the platform reports for a (source, target) language pair, mirrored so
/// routing is decidable — and testable — without the Translation framework or
/// its language assets, neither of which a CI runner has.
public enum TranslationPairStatus: Sendable, Equatable {
    /// Both languages are on the device: the native session can run now.
    case installed
    /// Supported, but the language assets must download first.
    case downloadable
    /// The platform cannot translate this pair.
    case unsupported
    /// The source language could not be identified, or the OS predates the
    /// native session.
    case undetermined
}

/// Which engine translates a clip.
public enum TranslationRoute: Sendable, Equatable {
    /// Apple's Translation framework: a purpose-built engine that outruns
    /// prompting the model once warm. A first SHORT translation can still pay a
    /// cold start and lose to the model, so this is a warm-path advantage, not a
    /// per-call guarantee.
    case native
    /// The Foundation Models prompt Gancho shipped with.
    case languageModel

    /// Only an INSTALLED pair goes native.
    ///
    /// `downloadable` deliberately does not: a download is granted through
    /// Apple's own sheet, which only a SwiftUI `translationTask` can present, and
    /// a package service has no view to present it from. Routing it native would
    /// fail every time rather than prompt, so it takes the model path instead —
    /// the same answer the user got before this existed.
    public static func route(for status: TranslationPairStatus) -> TranslationRoute {
        status == .installed ? .native : .languageModel
    }
}

/// The seams a translation runs through, injectable so routing, fallback,
/// cancellation and privacy can be tested without language assets or a model.
public struct TranslationEngines: Sendable {
    /// The dominant language of the text, or nil when it cannot be told.
    public var identifySource: @Sendable (String) -> Locale.Language?
    /// What the platform can do for this pair right now.
    public var pairStatus:
        @Sendable (Locale.Language, Locale.Language) async -> TranslationPairStatus
    /// The native session: (text, source, target).
    public var native: @Sendable (String, Locale.Language, Locale.Language) async throws -> String
    /// The model fallback: (text, English name of the target language).
    public var languageModel: @Sendable (String, String) async throws -> String

    public init(
        identifySource: @escaping @Sendable (String) -> Locale.Language?,
        pairStatus:
            @escaping @Sendable (Locale.Language, Locale.Language) async -> TranslationPairStatus,
        native:
            @escaping @Sendable (String, Locale.Language, Locale.Language) async throws -> String,
        languageModel: @escaping @Sendable (String, String) async throws -> String
    ) {
        self.identifySource = identifySource
        self.pairStatus = pairStatus
        self.native = native
        self.languageModel = languageModel
    }

    /// The real engines. `LanguageAvailability`, `TranslationSession` and
    /// `LanguageModelSession` are created per call and never stored: the first
    /// two are plain non-`Sendable` classes, so holding one across isolation is
    /// exactly what Swift 6 forbids.
    public static let live = TranslationEngines(
        identifySource: { text in
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(text)
            guard let language = recognizer.dominantLanguage, language != .undetermined else {
                return nil
            }
            return Locale.Language(identifier: language.rawValue)
        },
        pairStatus: { source, target in
            guard #available(macOS 26.0, iOS 26.0, *) else { return .undetermined }
            switch await LanguageAvailability().status(from: source, to: target) {
            case .installed: return .installed
            case .supported: return .downloadable
            case .unsupported: return .unsupported
            @unknown default: return .undetermined
            }
        },
        native: { text, source, target in
            guard #available(macOS 26.0, iOS 26.0, *) else {
                throw AnnotationError.backendUnavailable
            }
            return try await TranslationSession(installedSource: source, target: target)
                .translate(text).targetText
        },
        languageModel: { text, englishName in
            guard #available(macOS 26.0, iOS 26.0, *), SmartPasteService.isAvailable else {
                throw AnnotationError.backendUnavailable
            }
            let session = LanguageModelSession(
                instructions: SmartPasteService.translateInstructions(to: englishName))
            return try await session.respond(to: text).content
        })
}

#if DEBUG
    import Foundation
    import GanchoAI

    /// Injected only by shells launched against disposable UI-test stores.
    public enum TranslationUITestFixture {
        public static let engines = TranslationEngines(
            identifySource: { _ in Locale.Language(identifier: "en") },
            pairStatus: { _, target in
                target.minimalIdentifier == "es" ? .installed : .unsupported
            },
            native: { _, _, _ in "Traducción sintética" },
            languageModel: { _, _ in throw AnnotationError.backendUnavailable },
            modelAvailable: { false })
    }
#endif

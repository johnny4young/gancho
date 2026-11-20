#if DEBUG
    import Foundation
    import GanchoAI

    /// Injected only by shells launched against disposable UI-test stores.
    public enum TranslationUITestFixture {
        public static let engines = engines(stalled: false)

        /// A translation that never finishes, to test the panel while a transform runs.
        public static let stalledEngines = engines(stalled: true)

        private static func engines(stalled: Bool) -> TranslationEngines {
            TranslationEngines(
                identifySource: { _ in Locale.Language(identifier: "en") },
                pairStatus: { _, target in
                    target.minimalIdentifier == "es" ? .installed : .unsupported
                },
                native: { _, _, _ in
                    if stalled { try await Task.sleep(for: .seconds(3_600)) }
                    return "Traducción sintética"
                },
                languageModel: { _, _ in throw AnnotationError.backendUnavailable },
                modelAvailable: { false })
        }
    }
#endif

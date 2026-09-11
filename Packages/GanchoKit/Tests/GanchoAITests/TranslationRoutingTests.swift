import Foundation
import Testing

@testable import GanchoAI

/// Routing between Apple's native Translation session and the model fallback.
///
/// Every engine here is a fake. CI has neither Apple Intelligence nor installed
/// translation assets, so an assertion about a REAL translation would pass or
/// skip for reasons unrelated to this code; what must hold regardless of the
/// machine is which engine gets asked, with what text, and what happens when it
/// fails or the request is cancelled.
@Suite("Native translation routing")
struct TranslationRoutingTests {
    /// What each engine was handed, recorded across `@Sendable` async closures.
    private actor Calls {
        var native: [String] = []
        var model: [(text: String, englishName: String)] = []
        var statusQueries = 0

        func recordNative(_ text: String) { native.append(text) }
        func recordModel(_ text: String, _ name: String) { model.append((text, name)) }
        func recordStatusQuery() { statusQueries += 1 }
    }

    private struct NativeFailure: Error {}

    private func engines(
        calls: Calls,
        source: Locale.Language? = Locale.Language(identifier: "en"),
        status: TranslationPairStatus,
        native: @escaping @Sendable () throws -> String = { "native" }
    ) -> TranslationEngines {
        TranslationEngines(
            identifySource: { _ in source },
            pairStatus: { _, _ in
                await calls.recordStatusQuery()
                return status
            },
            native: { text, _, _ in
                await calls.recordNative(text)
                return try native()
            },
            languageModel: { text, name in
                await calls.recordModel(text, name)
                return "model"
            })
    }

    private let spanish = Locale.Language(identifier: "es")

    @Test("Only an installed pair routes native")
    func routeIsNativeOnlyForInstalledPairs() {
        #expect(TranslationRoute.route(for: .installed) == .native)
        // A downloadable pair needs Apple's download sheet, which only a view
        // can present — so it must NOT route native from a service.
        #expect(TranslationRoute.route(for: .downloadable) == .languageModel)
        #expect(TranslationRoute.route(for: .unsupported) == .languageModel)
        #expect(TranslationRoute.route(for: .undetermined) == .languageModel)
    }

    @Test("An installed pair uses the native session and never the model")
    func installedPairUsesNative() async throws {
        let calls = Calls()
        let result = try await SmartPasteService().translate(
            "Good morning", to: spanish, engines: engines(calls: calls, status: .installed))

        #expect(result == "native")
        #expect(await calls.native.count == 1)
        #expect(await calls.model.isEmpty, "an installed pair must not also pay for the model")
    }

    @Test("A downloadable pair falls back to the model")
    func downloadablePairFallsBack() async throws {
        let calls = Calls()
        let result = try await SmartPasteService().translate(
            "Good morning", to: spanish, engines: engines(calls: calls, status: .downloadable))

        #expect(result == "model")
        #expect(await calls.native.isEmpty, "routing native here would fail every time")
    }

    @Test("An unidentifiable source skips the availability check entirely")
    func unidentifiableSourceGoesStraightToTheModel() async throws {
        let calls = Calls()
        let result = try await SmartPasteService().translate(
            "12345", to: spanish,
            engines: engines(calls: calls, source: nil, status: .installed))

        #expect(result == "model")
        // Without a source there is no pair to ask about, and asking with a
        // guessed one could route a text native that the session cannot read.
        #expect(await calls.statusQueries == 0)
        #expect(await calls.native.isEmpty)
    }

    @Test("A failed native translation falls back to the model")
    func nativeFailureFallsBack() async throws {
        let calls = Calls()
        let result = try await SmartPasteService().translate(
            "Good morning", to: spanish,
            engines: engines(calls: calls, status: .installed, native: { throw NativeFailure() }))

        #expect(result == "model")
        #expect(await calls.native.count == 1)
        #expect(await calls.model.count == 1)
    }

    @Test("Cancellation is rethrown, never retried on the slower engine")
    func cancellationIsNotSilentlyRetried() async {
        let calls = Calls()
        await #expect(throws: CancellationError.self) {
            try await SmartPasteService().translate(
                "Good morning", to: spanish,
                engines: engines(
                    calls: calls, status: .installed, native: { throw CancellationError() }))
        }
        #expect(await calls.model.isEmpty, "an abandoned request must not start the fallback")
    }

    @Test("Both routes receive the same redacted text")
    func bothRoutesAreRedactedAlike() async throws {
        // Redacting only ahead of the model would hand the native session the
        // raw secret. Derived from the sanitizer itself, and asserted to differ
        // from the input, so this cannot pass by the sanitizer doing nothing.
        let input = "card 4111 1111 1111 1111 for the renewal"
        let redacted = ModelInputSanitizer.sanitized(input)
        #expect(redacted != input, "the planted secret must be one the sanitizer redacts")

        let native = Calls()
        _ = try await SmartPasteService().translate(
            input, to: spanish, engines: engines(calls: native, status: .installed))
        #expect(await native.native == [redacted])

        let model = Calls()
        _ = try await SmartPasteService().translate(
            input, to: spanish, engines: engines(calls: model, status: .unsupported))
        #expect(await model.model.map(\.text) == [redacted])
    }

    @Test("The model fallback is told the target's English name")
    func fallbackGetsTheEnglishLanguageName() async throws {
        let calls = Calls()
        _ = try await SmartPasteService().translate(
            "Good morning", to: spanish, engines: engines(calls: calls, status: .unsupported))
        #expect(await calls.model.map(\.englishName) == ["Spanish"])
    }
}

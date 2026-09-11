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
        native: @escaping @Sendable () throws -> String = { "native" },
        model: @escaping @Sendable () throws -> String = { "model" }
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
                return try model()
            })
    }

    /// Runs `translate` in a task of its own, so a fake can cancel exactly that
    /// request, never the test's task, at the step the test is about.
    private func translateInOwnTask(engines: TranslationEngines) async -> Result<String, any Error>
    {
        await Task {
            try await SmartPasteService().translate(
                "Good morning", to: Locale.Language(identifier: "es"), engines: engines)
        }.result
    }

    /// Cancels the task the calling engine runs in. Deterministic, unlike racing
    /// `Task.cancel()` against a task that may not have reached that step yet.
    private static func cancelCurrentTask() {
        withUnsafeCurrentTask { task in
            if let task { task.cancel() }
        }
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

    @Test("A variant's region survives into the model's prompt")
    func variantSurvivesIntoTheModelPrompt() async throws {
        let calls = Calls()
        _ = try await SmartPasteService().translate(
            "Good morning", to: Locale.Language(identifier: "pt-PT"),
            engines: engines(calls: calls, status: .unsupported))

        let name = try #require(await calls.model.first?.englishName)
        let base = SmartPasteService.englishLanguageName(for: Locale.Language(identifier: "pt"))
        // Asserted against the base name rather than CLDR's exact wording: what
        // must hold is that Portugal survived, not how Foundation phrases it.
        #expect(name != base)
        #expect(name.contains("Portugal"))
    }

    @Test("A base language keeps its plain name; a non-default script does not collapse")
    func baseNamesStayPlainAndScriptsSurvive() {
        let name = { SmartPasteService.englishLanguageName(for: Locale.Language(identifier: $0)) }
        // Codes the app offers keep the plain names the shipped prompt always used.
        #expect(name("zh") == "Chinese")
        #expect(name("pt") == "Portuguese")
        // Traditional is not CLDR's default script for `zh`, so it must not be
        // requested as plain "Chinese".
        #expect(name("zh-Hant") != name("zh"))
    }

    @Test(
        "A cancellation during the availability query starts no engine",
        arguments: [TranslationPairStatus.installed, .downloadable])
    func cancellationDuringStatusQueryStartsNoEngine(status: TranslationPairStatus) async {
        let calls = Calls()
        var routed = engines(calls: calls, status: status)
        routed.pairStatus = { _, _ in
            // The query cannot throw, so cancelling is all it can do.
            Self.cancelCurrentTask()
            return status
        }
        let result = await translateInOwnTask(engines: routed)

        #expect(throws: CancellationError.self) { try result.get() }
        #expect(await calls.native.isEmpty)
        #expect(await calls.model.isEmpty)
    }

    @Test("A request cancelled before its source is identified starts no engine")
    func cancellationBeforeIdentificationStartsNoEngine() async {
        let calls = Calls()
        var unidentified = engines(calls: calls, source: nil, status: .installed)
        unidentified.identifySource = { _ in
            Self.cancelCurrentTask()
            return nil
        }
        let result = await translateInOwnTask(engines: unidentified)

        #expect(throws: CancellationError.self) { try result.get() }
        #expect(await calls.model.isEmpty)
    }

    @Test(
        "An answer that arrives after cancellation is discarded, not delivered",
        arguments: [TranslationPairStatus.installed, .unsupported])
    func lateAnswerAfterCancellationIsDiscarded(status: TranslationPairStatus) async {
        let calls = Calls()
        let result = await translateInOwnTask(
            engines: engines(
                calls: calls, status: status,
                native: {
                    Self.cancelCurrentTask()
                    return "native"
                },
                model: {
                    Self.cancelCurrentTask()
                    return "model"
                }))

        #expect(throws: CancellationError.self) { try result.get() }
        // Exactly one engine ran: the discarded answer is not retried on the other.
        #expect(await calls.native.count + calls.model.count == 1)
    }

    @Test("A native failure while cancelled does not start the fallback")
    func nativeFailureWhileCancelledDoesNotFallBack() async {
        let calls = Calls()
        let result = await translateInOwnTask(
            engines: engines(
                calls: calls, status: .installed,
                native: {
                    Self.cancelCurrentTask()
                    throw NativeFailure()
                }))

        #expect(throws: CancellationError.self) { try result.get() }
        #expect(await calls.model.isEmpty, "an abandoned request must not start the fallback")
    }
}

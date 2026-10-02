import Foundation
import Testing

@testable import GanchoAI

@Suite("Translation capabilities independent of Apple Intelligence")
struct TranslationCapabilityTests {
    private func engines(
        status: TranslationPairStatus, model: Bool, knownSource: Bool = true,
        nativeFails: Bool = false, nativeResult: String = "translated"
    ) -> TranslationEngines {
        TranslationEngines(
            identifySource: { _ in knownSource ? Locale.Language(identifier: "en") : nil },
            pairStatus: { _, _ in status },
            native: { _, _, _ in
                if nativeFails { throw AnnotationError.backendUnavailable }
                return nativeResult
            },
            languageModel: { _, _ in "fallback" }, modelAvailable: { model })
    }

    @Test(
        arguments: [
            TranslationPairStatus.installed, .downloadable, .unsupported, .undetermined
        ], [false, true])
    func capabilityMatrix(status: TranslationPairStatus, model: Bool) async throws {
        let destinations = try await TranslationCapabilities.destinations(
            text: "Good morning", enabled: true, engines: engines(status: status, model: model))
        #expect(destinations.count == TranslationCapabilities.targetCodes.count - 1)
        #expect(!destinations.contains { $0.code == "en" }, "the source is never a destination")
        #expect(destinations.allSatisfy { $0.isAvailable == (status == .installed || model) })
    }

    @Test func unknownSource() async throws {
        let targets = try await TranslationCapabilities.destinations(
            text: "?", enabled: true,
            engines: engines(status: .installed, model: false, knownSource: false))
        #expect(targets.allSatisfy { $0.status == .undetermined && !$0.isAvailable })
        #expect(targets.count == TranslationCapabilities.targetCodes.count)
    }

    @Test func optOutAndEmptyQuery() async throws {
        for (text, enabled) in [("Good morning", false), (" \n", true)] {
            #expect(
                try await TranslationCapabilities.destinations(
                    text: text, enabled: enabled, engines: engines(status: .installed, model: true)
                ).isEmpty)
        }
    }

    @Test func nativeWithoutModel() async throws {
        #expect(
            try await SmartPasteService().translate(
                "Good morning", to: Locale.Language(identifier: "es"),
                engines: engines(status: .installed, model: false)) == "translated")
    }

    @Test func unavailableFallbackIsNotStarted() async throws {
        for status in [TranslationPairStatus.installed, .downloadable, .unsupported, .undetermined]
        {
            await #expect(throws: AnnotationError.backendUnavailable) {
                try await SmartPasteService().translate(
                    "Good morning", to: Locale.Language(identifier: "es"),
                    engines: engines(status: status, model: false, nativeFails: true))
            }
        }
    }

    @Test func emptyAnswerNeverBecomesCopyableContent() async throws {
        await #expect(throws: AnnotationError.backendUnavailable) {
            try await SmartPasteService().translate(
                "Good morning", to: Locale.Language(identifier: "es"),
                engines: engines(status: .installed, model: false, nativeResult: " \n"))
        }
    }

    @Test func cancellationDuringAvailability() async throws {
        var injected = engines(status: .installed, model: false)
        injected.pairStatus = { _, _ in
            withUnsafeCurrentTask { $0?.cancel() }
            return .installed
        }
        let cancelledEngines = injected
        let result = await Task {
            try await TranslationCapabilities.destinations(
                text: "Good morning", enabled: true, engines: cancelledEngines)
        }.result
        #expect(throws: CancellationError.self) { try result.get() }
    }

    @Test func availabilityChangesAreNotCachedByPolicy() async throws {
        let installed = try await TranslationCapabilities.destinations(
            text: "Good morning", enabled: true, engines: engines(status: .installed, model: false))
        let revoked = try await TranslationCapabilities.destinations(
            text: "Good morning", enabled: true,
            engines: engines(status: .downloadable, model: false))
        #expect(installed.allSatisfy { $0.isAvailable })
        #expect(revoked.allSatisfy { !$0.isAvailable })
    }
}

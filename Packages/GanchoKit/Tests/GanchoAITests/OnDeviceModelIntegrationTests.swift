import Foundation
import FoundationModels
import GanchoKit
import Testing

@testable import GanchoAI

/// Live runs against the on-device Foundation Models system model and the
/// real NLContextualEmbedding assets.
///
/// Opt-in only (`GANCHO_AI_INTEGRATION=1`): needs Apple Intelligence enabled
/// and model assets on device — neither exists on CI runners. Latency varies
/// with thermals, so budgets here are generous; the numbers that matter are
/// PRINTED for the spike report.
@Suite(
    "On-device model — live integration",
    .enabled(if: ProcessInfo.processInfo.environment["GANCHO_AI_INTEGRATION"] == "1"),
    .serialized)
struct OnDeviceModelIntegrationTests {
    static let sampleClips: [String] = [
        "https://developer.apple.com/documentation/foundationmodels",
        "meet me at the coffee shop on 5th at 3pm tomorrow",
        "SELECT id, title FROM clips WHERE kind = 'url' ORDER BY created_at DESC;",
        "{\"name\": \"gancho\", \"version\": \"0.1.0\", \"private\": true}",
        "#FF6B35",
        "support@example.com",
        "+1 (415) 555-0199",
        "550e8400-e29b-41d4-a716-446655440000",
        "func capture() async throws -> PasteboardCapture { fatalError() }",
        "Pick up the dry cleaning before Thursday, ticket 4521",
        "The quarterly numbers look better than expected, let's review Monday",
        "docker run --rm -it -v $(pwd):/work swift:6.2 bash",
        "Dear team, please find attached the updated onboarding guide",
        "WiFi: CasaYoung / Password hint: the usual one plus the year",
        "127.0.0.1 staging.gancho.test",
        "TODO: rotate the staging credentials before the Friday deploy",
        "git rebase -i HEAD~3 && git push --force-with-lease",
        "Flight AA1234 SFO→JFK departs 8:45am gate B22",
        "Total: $1,284.50 (includes 8.5% tax)",
        "La reunión se movió para el jueves a las 10am, avísale al equipo",
    ]

    @Test("20 sample clips annotate with guaranteed structured output")
    func annotateTwentyClips() async throws {
        try #require(FoundationModelAnnotator.isAvailable, "Apple Intelligence must be enabled")
        let annotator = FoundationModelAnnotator()
        var latencies: [Duration] = []

        for clip in Self.sampleClips {
            let start = ContinuousClock.now
            let annotation = try await annotator.annotate(clip)
            latencies.append(ContinuousClock.now - start)

            #expect(!annotation.title.isEmpty)
            #expect(annotation.title.count <= 60)
            #expect(ClipContentKind.allCases.contains(annotation.kind))
        }

        let total = latencies.reduce(Duration.zero, +)
        let sorted = latencies.sorted()
        print("FM annotate: n=\(latencies.count) total=\(total)")
        print(
            "FM annotate: median=\(sorted[sorted.count / 2]) p95=\(sorted[Int(0.95 * Double(sorted.count))]) max=\(sorted.last!)"
        )
    }

    @Test("Context budget: clamped input fits the 4,096-token shared window")
    func contextBudget() async throws {
        try #require(FoundationModelAnnotator.isAvailable, "Apple Intelligence must be enabled")
        guard #available(macOS 26.4, iOS 26.4, *) else {
            print("FM tokenCount unavailable (<26.4) — budget verified by clamp only")
            return
        }
        let model = SystemLanguageModel.default
        print("FM contextSize:", model.contextSize)

        // Worst-case clamped input (1,500 chars of dense prose).
        let clamped = String(
            String(repeating: "rotate the staging credentials before the deploy ", count: 40)
                .prefix(1500))
        let tokens = try await model.tokenCount(for: Prompt(clamped))
        print("FM tokenCount for 1500-char clamp:", tokens)
        // Instructions + schema + output must fit in the remainder.
        #expect(tokens < model.contextSize / 2, "clamp leaves no room for output")
    }

    @Test("Oversized input still annotates thanks to the clamp")
    func oversizedInputClamped() async throws {
        try #require(FoundationModelAnnotator.isAvailable, "Apple Intelligence must be enabled")
        let annotator = FoundationModelAnnotator()
        let huge = String(repeating: "log line with noise 0xDEADBEEF\n", count: 2000)
        let annotation = try await annotator.annotate(huge)
        #expect(!annotation.title.isEmpty)
    }

    @Test("NLContextualEmbedding emits 512-dim vectors and ranks by meaning")
    func realEmbeddings() async throws {
        let embedder = try #require(ContextualSentenceEmbedder())
        if !embedder.hasAvailableAssets {
            try await embedder.requestAssets()
        }
        print("NL embedding dimension:", embedder.dimension)
        #expect(embedder.dimension == 512)

        let start = ContinuousClock.now
        let groceries = try embedder.vector(for: "buy milk and eggs at the store")
        let perVector = ContinuousClock.now - start
        print("NL embedding latency (1 sentence):", perVector)

        var index = EmbeddingIndex(dimension: embedder.dimension)
        let groceriesID = UUID()
        try index.insert(id: groceriesID, vector: groceries)
        try index.insert(
            id: UUID(), vector: embedder.vector(for: "rotate the ssh keys on the bastion host"))
        try index.insert(
            id: UUID(), vector: embedder.vector(for: "the deploy pipeline failed again"))

        let hits = try index.search(
            embedder.vector(for: "purchase groceries: milk, eggs"), topK: 3)
        #expect(hits.first?.id == groceriesID, "semantic neighbor must rank first")
        print("NL search scores:", hits.map(\.score))
    }

    @Test("Smart Paste rewrites a clip on-device (summarize)")
    func smartPasteSummarizeLive() async throws {
        try #require(SmartPasteService.isAvailable, "Apple Intelligence must be enabled")
        let input = """
            Hey team, the Friday deploy is pushed to Monday because staging is flaky. \
            Please rotate the staging credentials beforehand and re-run the smoke suite.
            """
        let out = try await SmartPasteService().transform(input, action: .summarize)
        print("Smart Paste (summarize):", out)
        #expect(!out.isEmpty)
    }

    @Test("Smart Paste redacts PII deterministically through the service")
    func smartPasteRedactLive() async throws {
        let input =
            "checkout failed for jane.doe@acme.com (+1 415-555-0199), card 4111 1111 1111 1111"
        let out = try await SmartPasteService().transform(input, action: .redactPII)
        print("Smart Paste (redact PII):", out)
        #expect(out.contains("[email]"))
        #expect(out.contains("[phone]"))
        #expect(out.contains("[card]"))
        #expect(!out.contains("jane.doe@acme.com"))
    }

    @Test("Ask your clipboard answers grounded in the provided clips")
    func askClipboardLive() async throws {
        try #require(ClipboardQAService.isAvailable, "Apple Intelligence must be enabled")
        let sources = [
            "Flight AA1234 SFO->JFK departs 8:45am gate B22",
            "Total: $1,284.50 (includes 8.5% tax)",
            "La reunion se movio para el jueves a las 10am",
        ]
        let answer = try await ClipboardQAService().answer(
            question: "What time does my flight leave?", sources: sources)
        print("Ask your clipboard:", answer)
        #expect(!answer.isEmpty)
    }
}

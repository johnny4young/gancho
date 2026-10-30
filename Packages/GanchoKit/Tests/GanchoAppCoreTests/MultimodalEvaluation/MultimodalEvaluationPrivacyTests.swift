import Foundation
import GanchoAI
import GanchoKit
import Testing

/// Privacy fixtures kept apart from the relevance corpus. Real Vision OCR, no model assets.
@Suite("Multimodal evaluation privacy")
struct MultimodalEvaluationPrivacyTests {
    private typealias Corpus = MultimodalEvaluationCorpus

    private static let secret = Corpus.Capture(
        key: "privacy.secret", id: UUID(),
        scene: .dialog(
            title: "Access Key", message: "Do not share this key.",
            code: "AKIAIOSFODNN7EXAMPLE"))
    private static let expired = Corpus.Capture(
        key: "privacy.expired", id: UUID(),
        scene: .dialog(title: "Quarterly Roadmap", message: "Ship the beta.", code: "RDM2026"))
    private static let sensitive = Corpus.Capture(
        key: "privacy.sensitive", id: UUID(), scene: .text("Vault phrase lantern harbor"))
    private static let visible = Corpus.Capture(
        key: "privacy.visible", id: UUID(),
        scene: .dialog(title: "Office Notice", message: "Lunch is at noon.", code: "VIS3141"))

    private func makeFixture() async throws -> MultimodalEvaluationFixture {
        try await MultimodalEvaluationFixture.make(
            captures: [Self.secret, Self.expired, Self.sensitive, Self.visible]
        ) { item in
            if item.id == Self.expired.id { item.expiresAt = .now.addingTimeInterval(-60) }
            if item.id == Self.sensitive.id { item.isSensitive = true }
        }
    }

    @Test("OCR that reads as a secret is never stored as searchable text")
    func secretOCRIsDropped() async throws {
        // Non-vacuous: Vision must actually read the key and the detector must flag it.
        let png = try SyntheticCaptureRenderer.png(for: Self.secret.scene)
        let read = try #require(try await ImageTextExtractor().extractText(from: png))
        #expect(SensitiveDataDetector().detect(read) != nil, "OCR read: \(read)")

        let fixture = try await makeFixture()
        #expect(fixture.searchableText[Self.secret.id] == nil)
        let lexical = OCRLexicalStrategy(store: fixture.store)
        #expect(try await lexical.rank("AKIAIOSFODNN7EXAMPLE", limit: 5).isEmpty)
    }

    @Test("Expired and sensitive clips never rank lexically; a visible one does")
    func lexicalVetoes() async throws {
        let fixture = try await makeFixture()
        let lexical = OCRLexicalStrategy(store: fixture.store)
        #expect(try await lexical.rank("VIS3141", limit: 5) == [Self.visible.id])
        #expect(fixture.searchableText[Self.expired.id] != nil, "OCR must read the expired one")
        #expect(try await lexical.rank("RDM2026", limit: 5).isEmpty)
        #expect(try await lexical.rank("lantern", limit: 5).isEmpty)
    }

    @Test("Semantic ranking drops expired and sensitive clips even when every vector ties")
    func semanticVetoes() async throws {
        let fixture = try await makeFixture()
        let semantic = try OCRSemanticStrategy(fixture: fixture, embedder: ConstantEmbedding())
        let ranked = try await semantic.rank("anything", limit: 5)
        #expect(ranked == [Self.visible.id])
    }
}

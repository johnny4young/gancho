import Foundation
import Testing

@Suite("Multimodal retrieval strategies")
struct MultimodalRetrievalStrategyTests {
    private typealias Corpus = MultimodalEvaluationCorpus

    // Fixed ids put the unrelated note first in the tied semantic ranking.
    private static let unrelated = Corpus.Capture(
        key: "strategy.unrelated", id: Corpus.identifier(index: 200),
        scene: .text("Water the ferns on Sunday"))
    private static let literal = Corpus.Capture(
        key: "strategy.literal", id: Corpus.identifier(index: 201),
        scene: .text("Office notice VIS3141"))
    private static let shape = Corpus.Capture(
        key: "strategy.shape", id: UUID(),
        scene: .shapes([
            .init(
                kind: .circle, colour: .red, frame: CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2))
        ]))

    @Test("Semantic results keep literal matches first, then fill the limit")
    func literalMatchesComeFirst() async throws {
        let fixture = try await MultimodalEvaluationFixture.make(
            captures: [Self.unrelated, Self.literal])
        let semantic = try OCRSemanticStrategy(fixture: fixture, embedder: ConstantEmbedding())
        #expect(
            try await semantic.rank("VIS3141", limit: 5) == [Self.literal.id, Self.unrelated.id])
        #expect(try await semantic.rank("VIS3141", limit: 1) == [Self.literal.id])
    }

    @Test("A fixture removes its blob directory when released")
    func blobDirectoryIsRemoved() async throws {
        var fixture: MultimodalEvaluationFixture? = try await .make(captures: [Self.shape])
        let directory = try #require(fixture?.blobDirectory)
        #expect(FileManager.default.fileExists(atPath: directory.path))
        fixture = nil
        #expect(!FileManager.default.fileExists(atPath: directory.path))
    }
}

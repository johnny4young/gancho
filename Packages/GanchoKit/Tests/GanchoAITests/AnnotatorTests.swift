import Foundation
import GanchoKit
import Testing

@testable import GanchoAI

@Suite("HeuristicAnnotator — deterministic fallback")
struct HeuristicAnnotatorTests {
    let annotator = HeuristicAnnotator()

    @Test("URLs title as host + leading path")
    func urlTitle() async throws {
        let annotation = try await annotator.annotate(
            "https://developer.apple.com/documentation/foundationmodels/generable")
        #expect(annotation.kind == .url)
        #expect(annotation.title == "developer.apple.com/documentation")
    }

    @Test("Free text titles as its first line, clamped to six words")
    func textTitle() async throws {
        let annotation = try await annotator.annotate(
            "remember to rotate the staging credentials before the Friday deploy\nsecond line")
        #expect(annotation.kind == .text)
        #expect(annotation.title == "remember to rotate the staging credentials")
    }

    @Test("Sensitive kinds never leak content into the title")
    func sensitiveTitles() async throws {
        let jwt = try await annotator.annotate(
            "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.c2lnbmF0dXJl")
        #expect(jwt.kind == .jwt)
        #expect(jwt.title == "JWT token")
        #expect(!jwt.title.contains("eyJ"))
    }

    @Test("Long single-token lines are length-clamped with an ellipsis")
    func longLineClamp() {
        let title = HeuristicAnnotator.clampedFirstLine(String(repeating: "a", count: 200))
        #expect(title.count <= 50)
        #expect(title.hasSuffix("…"))
    }
}

/// Scriptable annotator for tier-composition tests.
private struct StubAnnotator: ClipAnnotating {
    var result: Result<ClipAnnotation, AnnotationError>

    func annotate(_ text: String) async throws -> ClipAnnotation {
        try result.get()
    }
}

@Suite("TieredClipAnnotator — unavailable path")
struct TieredClipAnnotatorTests {
    @Test("Primary result wins when the model answers")
    func primaryWins() async throws {
        let tiered = TieredClipAnnotator(
            primary: StubAnnotator(result: .success(.init(title: "model", kind: .code))),
            fallback: HeuristicAnnotator())
        let annotation = try await tiered.annotate("let x = 1")
        #expect(annotation.title == "model")
    }

    @Test("Unavailable backend degrades to heuristics, not to an error")
    func unavailableFallsBack() async throws {
        let tiered = TieredClipAnnotator(
            primary: StubAnnotator(result: .failure(.backendUnavailable)),
            fallback: HeuristicAnnotator())
        let annotation = try await tiered.annotate("plain note about groceries")
        #expect(annotation.kind == .text)
        #expect(annotation.title == "plain note about groceries")
    }
}

@Suite("EmbeddingIndex — exact cosine search")
struct EmbeddingIndexTests {
    /// Deterministic pseudo-random vectors (LCG) so the benchmark and
    /// ranking assertions never flake.
    static func syntheticVector(seed: Int, dimension: Int) -> [Float] {
        var state = UInt64(bitPattern: Int64(seed &* 2_862_933_555_777_941_757 &+ 3_037_000_493))
        return (0..<dimension).map { _ in
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Float(Int64(bitPattern: state) % 1000) / 1000.0
        }
    }

    @Test("An identical vector scores ~1, an orthogonal one ~0")
    func cosineCorrectness() throws {
        var index = EmbeddingIndex(dimension: 4)
        let a = UUID()
        let b = UUID()
        try index.insert(id: a, vector: [1, 0, 0, 0])
        try index.insert(id: b, vector: [0, 1, 0, 0])

        let hits = try index.search([2, 0, 0, 0], topK: 2)
        #expect(hits.first?.id == a)
        #expect(abs(hits[0].score - 1) < 1e-5)
        #expect(abs(hits[1].score - 0) < 1e-5)
    }

    @Test("Dimension mismatches are rejected on insert and search")
    func dimensionGuards() throws {
        var index = EmbeddingIndex(dimension: 4)
        #expect(throws: EmbeddingError.dimensionMismatch(expected: 4, got: 3)) {
            try index.insert(id: UUID(), vector: [1, 2, 3])
        }
        try index.insert(id: UUID(), vector: [1, 0, 0, 0])
        #expect(throws: EmbeddingError.dimensionMismatch(expected: 4, got: 5)) {
            _ = try index.search([1, 0, 0, 0, 0], topK: 1)
        }
    }

    @Test("Zero vectors are rejected — they would NaN the ranking")
    func zeroVectorGuard() throws {
        var index = EmbeddingIndex(dimension: 4)
        #expect(throws: EmbeddingError.noVectors) {
            try index.insert(id: UUID(), vector: [0, 0, 0, 0])
        }
    }

    @Test("Top-K over 10k×512 vectors stays under the 100ms search budget")
    func searchBudgetAt10k() throws {
        var index = EmbeddingIndex(dimension: 512)
        for seed in 0..<10_000 {
            try index.insert(id: UUID(), vector: Self.syntheticVector(seed: seed, dimension: 512))
        }
        let query = Self.syntheticVector(seed: 4242, dimension: 512)

        let start = ContinuousClock.now
        let hits = try index.search(query, topK: 10)
        let elapsed = ContinuousClock.now - start

        #expect(hits.count == 10)
        // The query vector itself was inserted as seed 4242 — exact match wins.
        #expect(abs(hits[0].score - 1) < 1e-4)
        #expect(elapsed < .milliseconds(100), "search took \(elapsed)")
        print("cosine search over 10k×512:", elapsed)
    }
}

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

    /// Exactness at scale, asserted WITHOUT a clock.
    ///
    /// `search` promises an exact scan: every stored vector is scored, and the
    /// top-K is the true top-K. This plants ten vectors of known, strictly
    /// descending similarity among 10k random distractors and demands them
    /// back in exactly that order — so an approximate structure, an early
    /// exit, a partial scan, or a broken selection all fail here, on any
    /// machine, under any load.
    ///
    /// The plants go in LAST on purpose: anything that stops scanning early
    /// reads the distractors and misses every one of them.
    ///
    /// The wall-clock budget that used to live here now runs under
    /// `GANCHO_PERF=1` (`make bench`) — see `EmbeddingIndexPerformanceTests`.
    /// A one-shot timing assertion in the default suite measured the machine
    /// as much as the algorithm, and failed pushes of unrelated work whenever
    /// a build was running alongside it.
    @Test("Top-K over 10k×512 vectors is the true top-K, plants last")
    func exactTopKAt10k() throws {
        let distractors = 10_000
        var index = EmbeddingIndex(dimension: 512)
        for seed in 0..<distractors {
            try index.insert(
                id: UUID(), vector: SyntheticVectors.vector(seed: seed, dimension: 512))
        }

        // Seeded OUTSIDE the distractor range: a query that is also one of the
        // 10k would tie the top plant at cosine 1 and shift every rank by one.
        // Random 512-d vectors sit near cosine 0 (σ ≈ 1/√512 ≈ 0.044), so every
        // planted similarity here clears the distractor noise by many σ.
        let query = SyntheticVectors.vector(seed: 424_242, dimension: 512)
        let targets: [Float] = [1.0, 0.95, 0.9, 0.85, 0.8, 0.75, 0.7, 0.65, 0.6, 0.55]
        var planted: [UUID] = []
        for (offset, target) in targets.enumerated() {
            let id = UUID()
            planted.append(id)
            try index.insert(
                id: id,
                vector: SyntheticVectors.vector(cosine: target, to: query, seed: 900_000 + offset))
        }

        #expect(index.count == distractors + targets.count)
        let hits = try index.search(query, topK: targets.count)

        #expect(hits.map(\.id) == planted, "exact search must return the true top-K, in order")
        for (hit, target) in zip(hits, targets) {
            #expect(abs(hit.score - target) < 1e-3, "score \(hit.score) should be \(target)")
        }
    }
}

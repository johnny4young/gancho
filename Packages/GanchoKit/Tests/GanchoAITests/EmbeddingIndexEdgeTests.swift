import Foundation
import GanchoKit
import Testing

@testable import GanchoAI

@Suite("Embedding index edge cases")
struct EmbeddingIndexEdgeTests {
    @Test(
        "Non-finite and overflowing vectors cannot poison the index",
        arguments: [Float.infinity, -.infinity, .nan, .greatestFiniteMagnitude])
    func invalidVector(value: Float) throws {
        var index = EmbeddingIndex(dimension: 2)
        #expect(throws: EmbeddingError.noVectors) {
            try index.insert(id: UUID(), vector: [value, 1])
        }
        let id = UUID()
        try index.insert(id: id, vector: [1, 0])
        #expect(index.count == 1)
        #expect(throws: EmbeddingError.noVectors) {
            _ = try index.search([value, 1], topK: 1)
        }
        let valid = try index.search([1, 0], topK: 1)
        #expect(valid.first?.id == id)
        #expect(valid.first?.score == 1)
    }

    @Test(
        "Ties preserve insertion order, including ties at the cutoff",
        arguments: [0, 1, 2, 7, 31, 200, Int.max])
    func ties(limit: Int) throws {
        var index = EmbeddingIndex(dimension: 2)
        let ids = (0..<100).map { _ in UUID() }
        for id in ids { try index.insert(id: id, vector: [1, 0]) }
        let result = try index.search([1, 0], topK: limit)
        #expect(result.map(\.id) == Array(ids.prefix(limit)))
    }

    @Test(
        "Bounded ranking matches a full stable sort for every cutoff",
        arguments: [1, 2, 10, 50, 100, 201])
    func matchesReference(limit: Int) throws {
        var index = EmbeddingIndex(dimension: 2)
        let ids = (0..<200).map { _ in UUID() }
        let values: [Float] = (0..<200).map { Float(($0 * 17) % 31 - 15) / 20 }
        for (id, score) in zip(ids, values) {
            try index.insert(id: id, vector: [score, sqrt(1 - score * score)])
        }
        // Full retrieval establishes the exact Accelerate scores. The reference
        // sort deliberately ignores the optimized top-K selection path.
        let all = try index.search([1, 0], topK: ids.count)
        let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0.score) })
        let expected = ids.sorted { byID[$0]! > byID[$1]! }.prefix(limit)
        let result = try index.search([1, 0], topK: limit)
        #expect(result.map(\.id) == Array(expected))
    }
}

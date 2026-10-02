import Foundation
import Testing

@testable import GanchoKit

@Suite("Bounded exact top-K selection")
struct BoundedTopKTests {
    @Test(
        "Every insertion matches a full reference sort without retaining more than K",
        arguments: [-1, 0, 1, 2, 3, 7, 16, 100, Int.max])
    func matchesReference(limit: Int) {
        let values = (0..<100).map { ($0 * 37) % 103 }
        var top = BoundedTopK<Int>(limit: limit, by: >)
        #expect(top.sorted.isEmpty)
        for (offset, value) in values.enumerated() {
            top.insert(value)
            #expect(top.count <= max(0, limit))
            #expect(
                top.sorted == Array(values.prefix(offset + 1).sorted(by: >).prefix(max(0, limit))))
        }
    }

    @Test("Storage retrieval breaks ties by clip ID at the cutoff")
    func storageRankingTies() {
        let values: [(id: String, score: Float)] = [
            ("c", 0.5), ("best", 1), ("a", 0.5), ("worst", -1), ("b", 0.5)
        ]
        var top = BoundedTopK<GRDBClipboardStore.SemanticCandidate>(
            limit: 3, by: GRDBClipboardStore.candidatePrecedes)
        for value in values {
            top.insert(.init(id: value.id, score: value.score, updatedAt: .distantPast))
        }
        #expect(top.sorted.map(\.id) == ["best", "a", "b"])
    }
}

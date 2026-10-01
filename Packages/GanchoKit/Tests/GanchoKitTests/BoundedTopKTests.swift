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

    @Test("Storage retrieval preserves scan-order ties at the cutoff")
    func storageRankingTies() {
        let values: [(id: String, score: Float)] = [
            ("first", 0.5), ("best", 1), ("second", 0.5), ("worst", -1), ("third", 0.5)
        ]
        let selected = GRDBClipboardStore.partialTopK(values, count: 3)
        #expect(selected.map(\.id) == ["best", "first", "second"])
    }
}

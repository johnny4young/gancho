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

    @Test("Explicit scan-order ties remain stable at the cutoff")
    func storageRankingTies() {
        let values: [(id: String, score: Float)] = [
            ("first", 0.5), ("best", 1), ("second", 0.5), ("worst", -1), ("third", 0.5)
        ]
        var top = BoundedTopK<(offset: Int, score: Float)>(limit: 3) {
            $0.score == $1.score ? $0.offset < $1.offset : $0.score > $1.score
        }
        for (offset, value) in values.enumerated() { top.insert((offset, value.score)) }
        let selected = top.sorted.map { values[$0.offset] }
        #expect(selected.map(\.id) == ["best", "first", "second"])
    }
}

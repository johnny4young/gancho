import Foundation

/// Pure scoring over ranked id lists, so the arithmetic is testable without OCR or models.
struct MultimodalRetrievalScorecard {
    struct Bucket: Hashable, Comparable {
        let language: String
        let category: MultimodalEvaluationCorpus.Category
        let heldOut: Bool

        var label: String {
            "\(language)/\(category.rawValue)/\(heldOut ? "held-out" : "calibration")"
        }

        static func < (lhs: Bucket, rhs: Bucket) -> Bool { lhs.label < rhs.label }
    }

    struct Tally: Equatable {
        var answered = 0
        var recallSum = 0.0
        var reciprocalRankSum = 0.0
        /// Answered queries whose first result is an image that is not expected.
        var wrongTopImage = 0
        var unanswered = 0
        /// Unanswered queries that still returned something.
        var unansweredWithResults = 0
        var misses: [String] = []

        var recall: Double? { answered == 0 ? nil : recallSum / Double(answered) }
        var meanReciprocalRank: Double? {
            answered == 0 ? nil : reciprocalRankSum / Double(answered)
        }
    }

    let cutoff: Int
    let imageIDs: Set<UUID>
    private(set) var tallies: [Bucket: Tally] = [:]

    init(cutoff: Int, imageIDs: Set<UUID>) {
        self.cutoff = cutoff
        self.imageIDs = imageIDs
    }

    mutating func record(
        _ query: MultimodalEvaluationCorpus.Query, expected: Set<UUID>, ranked: [UUID]
    ) {
        let bucket = Bucket(
            language: query.language, category: query.category, heldOut: query.heldOut)
        var tally = tallies[bucket] ?? Tally()
        let top = Array(ranked.prefix(cutoff))
        if expected.isEmpty {
            tally.unanswered += 1
            if !top.isEmpty { tally.unansweredWithResults += 1 }
        } else {
            tally.answered += 1
            let found = expected.intersection(top).count
            tally.recallSum += Double(found) / Double(expected.count)
            if let rank = top.firstIndex(where: expected.contains) {
                tally.reciprocalRankSum += 1 / Double(rank + 1)
            }
            if found == 0 { tally.misses.append(query.name) }
            if let first = top.first, imageIDs.contains(first), !expected.contains(first) {
                tally.wrongTopImage += 1
            }
        }
        tallies[bucket] = tally
    }

    /// Totals across every bucket matching `filter`.
    func total(where filter: (Bucket) -> Bool = { _ in true }) -> Tally {
        tallies.filter { filter($0.key) }.values.reduce(into: Tally()) { sum, tally in
            sum.answered += tally.answered
            sum.recallSum += tally.recallSum
            sum.reciprocalRankSum += tally.reciprocalRankSum
            sum.wrongTopImage += tally.wrongTopImage
            sum.unanswered += tally.unanswered
            sum.unansweredWithResults += tally.unansweredWithResults
            sum.misses += tally.misses
        }
    }
}

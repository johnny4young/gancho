import Foundation
import Testing

@testable import GanchoDesign

@Suite("Redaction — bar widths that vary by row and never jitter")
struct RedactionTests {
    @Test("The widths depend on the seed alone and repeat every twenty rows")
    func stable() {
        for seed in 0..<20 {
            #expect(Redaction.widths(seed: seed) == Redaction.widths(seed: seed + 20))
        }
        #expect(Redaction.widths(seed: 0) == (148, 58))
        #expect(Redaction.widths(seed: 7) == (90, 100))
        let id = UUID(uuid: (3, 4, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9, 9))
        #expect(Redaction.seed(for: id) == 7, "the clip's id, nothing about its content")
    }

    @Test("Neighbouring rows differ, and every width comes from the fixed sets")
    func varied() {
        let rows = (0..<20).map { Redaction.widths(seed: $0) }
        for (row, next) in zip(rows, rows.dropFirst()) {
            #expect(row.headline != next.headline)
            #expect(row.detail != next.detail)
        }
        #expect(Set(rows.map(\.headline)) == Set(Redaction.headlineWidths))
        #expect(Set(rows.map(\.detail)) == Set(Redaction.detailWidths))
    }

    @Test("Any seed is in range, negative and extreme ones too")
    func anySeed() {
        for seed in [-1, -20, Int.min, Int.max] {
            let widths = Redaction.widths(seed: seed)
            #expect(Redaction.headlineWidths.contains(widths.headline))
            #expect(Redaction.detailWidths.contains(widths.detail))
        }
        let all = UUID(uuid: (255, 255, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        #expect(Redaction.seed(for: all) == 510)
    }
}

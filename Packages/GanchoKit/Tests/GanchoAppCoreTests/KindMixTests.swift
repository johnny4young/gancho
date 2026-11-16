import GanchoKit
import Testing

@testable import GanchoAppCore

@Suite("Kind mix — a board's kinds bucketed like the filter pills")
struct KindMixTests {
    @Test("Kinds fold into their pill and sort by count")
    func bucketsAndSorts() {
        let mix = ClipKindFilter.mix(of: [
            .color: 9, .image: 6, .url: 5, .text: 2, .richText: 1, .json: 1, .uuid: 1
        ])
        #expect(
            mix == [
                KindMixSegment(filter: .colors, count: 9),
                KindMixSegment(filter: .images, count: 6),
                KindMixSegment(filter: .links, count: 5),
                KindMixSegment(filter: nil, count: 3),
                KindMixSegment(filter: .code, count: 2)
            ])
    }

    @Test("Ties keep the pills' order, with the uncovered kinds last")
    func tiesFollowThePills() {
        let mix = ClipKindFilter.mix(of: [.secret: 2, .text: 2, .url: 2, .jwt: 0])
        #expect(mix.map(\.filter) == [.links, .secrets, nil])
    }

    @Test("Empty buckets are dropped and the segments add up to the total")
    func dropsEmptyAndSumsToTotal() {
        let perKind: [ClipContentKind: Int] = [.code: 3, .creditCard: 1, .image: 0]
        let mix = ClipKindFilter.mix(of: perKind)
        #expect(mix.map(\.filter) == [.code, .secrets])
        #expect(mix.reduce(0) { $0 + $1.count } == perKind.values.reduce(0, +))
        #expect(ClipKindFilter.mix(of: [:]).isEmpty)
    }
}

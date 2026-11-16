import GanchoKit

/// One segment of a board's kind-mix bar.
public struct KindMixSegment: Sendable, Equatable {
    /// nil for the kinds no filter pill covers (plain text, files, …), so the
    /// segments always add up to the board's total.
    public let filter: ClipKindFilter?
    public let count: Int

    public init(filter: ClipKindFilter?, count: Int) {
        self.filter = filter
        self.count = count
    }
}

extension ClipKindFilter {
    /// Buckets per-kind counts like the filter pills: largest first, ties in
    /// the pills' order with the uncovered kinds last, empty buckets dropped.
    public static func mix(of perKind: [ClipContentKind: Int]) -> [KindMixSegment] {
        let pills = allCases.filter { $0 != .all }
        var segments = pills.map { KindMixSegment(filter: $0, count: $0.count(in: perKind)) }
        let covered = segments.reduce(0) { $0 + $1.count }
        segments.append(KindMixSegment(filter: nil, count: perKind.values.reduce(0, +) - covered))
        return segments.enumerated()
            .filter { $0.element.count >= 1 }
            .sorted { lhs, rhs in
                lhs.element.count != rhs.element.count
                    ? lhs.element.count > rhs.element.count : lhs.offset < rhs.offset
            }
            .map(\.element)
    }
}

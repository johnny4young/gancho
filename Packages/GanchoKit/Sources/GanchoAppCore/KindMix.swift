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

    /// `mix(of:)` with its uncovered bucket split: plain and rich text are
    /// named, and what is left stays an unnamed count at the end.
    public static func captionedMix(of perKind: [ClipContentKind: Int]) -> [KindMixCaption] {
        let text = (perKind[.text] ?? 0) + (perKind[.richText] ?? 0)
        let segments = mix(of: perKind)
        var named = segments.compactMap { segment in
            segment.filter.map { KindMixCaption(label: .filter($0), count: segment.count) }
        }
        if text >= 1 { named.append(KindMixCaption(label: .text, count: text)) }
        let other = (segments.first { $0.filter == nil }?.count ?? 0) - text
        let sorted = named.enumerated()
            .sorted { lhs, rhs in
                lhs.element.count != rhs.element.count
                    ? lhs.element.count > rhs.element.count : lhs.offset < rhs.offset
            }
            .map(\.element)
        return sorted + (other >= 1 ? [KindMixCaption(label: .other, count: other)] : [])
    }
}

/// A kind-mix segment as the Library's bar captions it.
public struct KindMixCaption: Sendable, Equatable {
    public enum Label: Sendable, Equatable {
        case filter(ClipKindFilter)
        case text
        /// Kinds with no name on the bar (files, emails, …): a bare count.
        case other
    }

    public let label: Label
    public let count: Int

    public init(label: Label, count: Int) {
        self.label = label
        self.count = count
    }
}

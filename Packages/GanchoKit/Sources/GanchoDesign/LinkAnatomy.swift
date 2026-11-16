import Foundation

/// A link split into the parts a reader names. The segments tile the original
/// text in order, so the URL is shown as copied and never rebuilt.
public struct LinkAnatomy: Equatable, Sendable {
    public enum Part: String, CaseIterable, Sendable {
        case scheme, host, path, query, fragment

        public var accessibilityIdentifier: String { "peek-link-part-\(rawValue)" }
    }

    /// One part with its delimiters: `https://`, the authority (user, host and
    /// port), the path, `?query`, `#fragment`.
    public struct Segment: Equatable, Identifiable, Sendable {
        public let part: Part
        public let range: Range<String.Index>
        public let text: String

        public var id: Part { part }
    }

    /// A query parameter with its percent escapes decoded.
    public struct Parameter: Equatable, Sendable {
        public let name: String
        public let value: String

        public var accessibilityIdentifier: String { "peek-link-param-\(name)" }
    }

    /// The trimmed link the ranges index into.
    public let text: String
    public let segments: [Segment]
    public let parameters: [Parameter]
    /// The decoded fragment, nil when absent or empty.
    public let fragment: String?
    /// The decoded path for a headline, nil for a bare host or `/`.
    public let path: String?

    /// Nil for anything without an authority (`mailto:`, `tel:`, plain text)
    /// and for links past the preview bound.
    public init?(text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.utf8.count <= 4_000, let components = URLComponents(string: trimmed),
            let scheme = components.scheme, components.host?.isEmpty == false
        else { return nil }
        let scalars = trimmed.unicodeScalars
        let end = scalars.endIndex
        guard
            let authority = scalars.index(
                scalars.startIndex, offsetBy: scheme.unicodeScalars.count + 3, limitedBy: end),
            trimmed[..<authority].hasSuffix("://")
        else { return nil }
        // RFC 3986 order: the authority ends at the first `/`, `?` or `#`.
        let pathStart = scalars[authority...].firstIndex { "/?#".unicodeScalars.contains($0) }
        let queryStart = scalars[(pathStart ?? end)...].firstIndex { $0 == "?" || $0 == "#" }
        let fragmentStart = scalars[(queryStart ?? end)...].firstIndex { $0 == "#" }
        let bounds: [(Part, Range<String.Index>)] = [
            (.scheme, scalars.startIndex..<authority),
            (.host, authority..<(pathStart ?? end)),
            (.path, (pathStart ?? end)..<(queryStart ?? end)),
            (.query, (queryStart ?? end)..<(fragmentStart ?? end)),
            (.fragment, (fragmentStart ?? end)..<end)
        ]
        let segments = bounds.filter { !$0.1.isEmpty }.map {
            Segment(part: $0.0, range: $0.1, text: String(trimmed[$0.1]))
        }
        guard segments.contains(where: { $0.part == .host }) else { return nil }
        self.text = trimmed
        self.segments = segments
        func unescaped(_ raw: some StringProtocol) -> String {
            raw.removingPercentEncoding ?? String(raw)
        }
        parameters = trimmed[bounds[3].1].dropFirst().split(separator: "&").map { pair in
            let halves = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            return Parameter(
                name: unescaped(halves[0]), value: halves.count > 1 ? unescaped(halves[1]) : "")
        }
        let fragment = unescaped(trimmed[bounds[4].1].dropFirst())
        self.fragment = fragment.isEmpty ? nil : fragment
        let path = unescaped(trimmed[bounds[2].1])
        self.path = path.isEmpty || path == "/" ? nil : path
    }
}

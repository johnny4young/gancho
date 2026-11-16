import SwiftUI

/// Where a row marks the search query: each query word wherever it occurs,
/// ignoring case and accents. Presentation only; search decides what matches.
public enum ClipMatchHighlight {
    /// The merged, ordered ranges of every query word found in `text`.
    public static func ranges(of query: String, in text: String) -> [Range<String.Index>] {
        var found: [Range<String.Index>] = []
        for term in Set(query.split(whereSeparator: \.isWhitespace).map(String.init)) {
            var start = text.startIndex
            while start < text.endIndex,
                let match = text.range(
                    of: term, options: [.caseInsensitive, .diacriticInsensitive],
                    range: start..<text.endIndex), !match.isEmpty
            {
                found.append(match)
                start = match.upperBound
            }
        }
        found.sort { $0.lowerBound < $1.lowerBound }
        return found.reduce(into: []) { merged, next in
            if let last = merged.last, next.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, next.upperBound)
            } else {
                merged.append(next)
            }
        }
    }

    /// `text` with every match in ink, emphasised and underlined; its other
    /// attributes are kept.
    public static func marked(_ text: AttributedString, query: String) -> AttributedString {
        let plain = String(text.characters)
        var marked = text
        for range in ranges(of: query, in: plain) {
            let lower = plain.distance(from: plain.startIndex, to: range.lowerBound)
            let length = plain.distance(from: range.lowerBound, to: range.upperBound)
            let lo = marked.index(marked.startIndex, offsetByCharacters: lower)
            let hi = marked.index(lo, offsetByCharacters: length)
            marked[lo..<hi].foregroundColor = GanchoTokens.Palette.ink
            marked[lo..<hi].inlinePresentationIntent = .stronglyEmphasized
            marked[lo..<hi].underlineStyle = Text.LineStyle(
                pattern: .solid, color: GanchoTokens.Palette.ink3)
        }
        return marked
    }
}

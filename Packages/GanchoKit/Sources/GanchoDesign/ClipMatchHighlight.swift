import Foundation
import GanchoKit
import SwiftUI
import Synchronization

/// Where a row marks the search. Presentation only; search decides what matches.
public enum ClipMatchHighlight {
    /// A pattern runs on the main thread here, so it reads no further than a row shows.
    static let patternHaystackLimit = 500

    /// Every row of a list marks the same pattern: compile it once.
    private static let lastPattern = Mutex<(pattern: String, regex: NSRegularExpression?)?>(nil)

    /// The merged, ordered ranges `match` finds in `text`; none for an invalid
    /// pattern or one that only matches empty strings.
    public static func ranges(of match: ClipMatch, in text: String) -> [Range<String.Index>] {
        switch match {
        case .words(let query): words(query, in: text)
        case .pattern(let pattern): self.pattern(pattern, in: text)
        }
    }

    private static func words(_ query: String, in text: String) -> [Range<String.Index>] {
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
        return merged(found)
    }

    private static func pattern(_ pattern: String, in text: String) -> [Range<String.Index>] {
        guard let regex = regex(for: pattern) else { return [] }
        let string = text as NSString
        let haystack = NSRange(location: 0, length: min(string.length, patternHaystackLimit))
        // Widened to whole characters: `.` can match half of an emoji.
        let found = regex.matches(in: text, range: haystack)
            .filter { $0.range.length > 0 }
            .compactMap { Range(string.rangeOfComposedCharacterSequences(for: $0.range), in: text) }
        return merged(found)
    }

    private static func regex(for pattern: String) -> NSRegularExpression? {
        lastPattern.withLock { last in
            if let last, last.pattern == pattern { return last.regex }
            let regex = try? ClipSearchQuery.regularExpression(pattern)
            last = (pattern, regex)
            return regex
        }
    }

    private static func merged(_ found: [Range<String.Index>]) -> [Range<String.Index>] {
        found.sorted { $0.lowerBound < $1.lowerBound }.reduce(into: []) { merged, next in
            if let last = merged.last, next.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<max(last.upperBound, next.upperBound)
            } else {
                merged.append(next)
            }
        }
    }

    /// `text` with every match in ink, emphasised and underlined; its other
    /// attributes are kept.
    public static func marked(_ text: AttributedString, match: ClipMatch) -> AttributedString {
        let plain = String(text.characters)
        var marked = text
        for range in ranges(of: match, in: plain) {
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

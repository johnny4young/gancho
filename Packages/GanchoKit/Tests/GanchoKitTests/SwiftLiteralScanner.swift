import Foundation

/// One piece of a Swift string literal: static text, or a `\(…)` interpolation.
enum SwiftLiteralSegment: Equatable {
    case text(String)
    case interpolation(String)
}

/// A small scanner for Swift string literals, backing the localization sweep.
///
/// A regex alone cannot read a literal that contains an interpolation: the
/// character class the sweep used, `([^"\\]+)`, stops dead at the backslash, so
/// `Text("No clips for “\(query)”.")` produced no match at all and went
/// unchecked — which is exactly how that key shipped missing from the macOS
/// catalog while Spanish users read the English source string. Walking the
/// literal character by character keeps its interpolations (and the nested
/// string literals inside them) intact, so the catalog key can be rebuilt.
enum SwiftLiteralScanner {
    /// Scans the literal whose opening quote is at `start`.
    ///
    /// `segments` is nil for the literal forms this scanner deliberately does
    /// not model — a `"""` block, or one running past the end of its line.
    /// `end` always advances beyond `start` (past the whole literal, where
    /// there is one), so a caller sweeping a range makes progress instead of
    /// rescanning the same quote forever.
    static func scan(
        _ source: String, from start: String.Index
    ) -> (segments: [SwiftLiteralSegment]?, end: String.Index) {
        var index = source.index(after: start)
        if index < source.endIndex, source[index] == "\"" {
            let third = source.index(after: index)
            guard third < source.endIndex, source[third] == "\"" else {
                return ([], source.index(after: index))  // The empty literal, "".
            }
            return (nil, multilineEnd(source, from: source.index(after: third)))
        }
        var segments: [SwiftLiteralSegment] = []
        var text = ""
        while index < source.endIndex {
            let character = source[index]
            if character == "\\" {
                let escape = source.index(after: index)
                guard escape < source.endIndex else { break }
                if source[escape] == "(" {
                    if !text.isEmpty {
                        segments.append(.text(text))
                        text = ""
                    }
                    let interpolation = scanInterpolation(source, from: escape)
                    segments.append(.interpolation(interpolation.expression))
                    index = interpolation.end
                    continue
                }
                text.append(unescaped(source[escape]))
                index = source.index(after: escape)
                continue
            }
            if character == "\"" {
                if !text.isEmpty { segments.append(.text(text)) }
                return (segments, source.index(after: index))
            }
            if character == "\n" { return (nil, index) }
            text.append(character)
            index = source.index(after: index)
        }
        return (nil, source.endIndex)
    }

    /// Every catalog key a literal could resolve to, likeliest first.
    ///
    /// SwiftUI turns each interpolation into a format specifier while building
    /// the `LocalizedStringKey` — `%@` for a String or a nested `Text`, `%lld`
    /// for an Int — and source text alone carries no types. So the scanner
    /// offers both spellings per interpolation and the sweep counts the key as
    /// present when ANY combination is in the catalog; guessing wrong would
    /// otherwise fail a string that is perfectly well localized. The first
    /// candidate is the likelier reading, and is what a failure quotes.
    ///
    /// Returns empty past four interpolations rather than expanding 32
    /// candidates for a literal no translator would be handed anyway.
    static func localizedKeys(for segments: [SwiftLiteralSegment]) -> [String] {
        var keys = [""]
        for segment in segments {
            switch segment {
            case .text(let text):
                keys = keys.map { $0 + text }
            case .interpolation(let expression):
                guard keys.count <= 8 else { return [] }
                let specifiers = looksLikeInteger(expression) ? ["%lld", "%@"] : ["%@", "%lld"]
                keys = keys.flatMap { key in specifiers.map { key + $0 } }
            }
        }
        return keys
    }

    /// Every single-line string literal in `range`, skipping `//` comments.
    ///
    /// Used for bodies that are nothing but keys — a `switch` returning
    /// `LocalizedStringKey`, or an array of them.
    static func literals(
        in source: String, range: Range<String.Index>
    ) -> [[SwiftLiteralSegment]] {
        var found: [[SwiftLiteralSegment]] = []
        var index = range.lowerBound
        while index < range.upperBound {
            if startsLineComment(source, at: index) {
                index = endOfLine(source, from: index)
                continue
            }
            guard source[index] == "\"" else {
                index = source.index(after: index)
                continue
            }
            let scanned = scan(source, from: index)
            if let segments = scanned.segments, !segments.isEmpty { found.append(segments) }
            index = scanned.end
        }
        return found
    }

    /// The index of the delimiter closing the block opened at `openedAt`,
    /// stepping over nested delimiters, string literals and `//` comments.
    static func blockEnd(
        in source: String, openedAt: String.Index, open: Character, close: Character
    ) -> String.Index {
        var index = openedAt
        var depth = 0
        while index < source.endIndex {
            let character = source[index]
            if character == "\"" {
                index = scan(source, from: index).end
                continue
            }
            if startsLineComment(source, at: index) {
                index = endOfLine(source, from: index)
                continue
            }
            if character == open { depth += 1 }
            if character == close {
                depth -= 1
                if depth == 0 { return index }
            }
            index = source.index(after: index)
        }
        return source.endIndex
    }

    /// Scans from the `(` of a `\(…)` interpolation to its matching `)`,
    /// stepping over nested parentheses and nested string literals — a nested
    /// `"\(Text("Waiting to sync")) · \(count)"` must not end at the inner `)`.
    private static func scanInterpolation(
        _ source: String, from openParen: String.Index
    ) -> (expression: String, end: String.Index) {
        let start = source.index(after: openParen)
        var index = start
        var depth = 1
        while index < source.endIndex {
            let character = source[index]
            if character == "\"" {
                index = scan(source, from: index).end
                continue
            }
            if character == "(" { depth += 1 }
            if character == ")" {
                depth -= 1
                if depth == 0 {
                    return (String(source[start..<index]), source.index(after: index))
                }
            }
            index = source.index(after: index)
        }
        return (String(source[start...]), source.endIndex)
    }

    /// The index just past the `"""` closing a multiline literal.
    private static func multilineEnd(_ source: String, from start: String.Index) -> String.Index {
        var index = start
        var quotes = 0
        while index < source.endIndex {
            quotes = source[index] == "\"" ? quotes + 1 : 0
            index = source.index(after: index)
            if quotes == 3 { return index }
        }
        return source.endIndex
    }

    /// The literal character an escape sequence stands for, so `\"` and `\n`
    /// reconstruct the key a translator actually sees. A `\u{…}` escape is NOT
    /// decoded — its `u` survives and the rebuilt key won't match the catalog.
    /// No app literal uses one today; if that changes, the sweep reports a
    /// missing key rather than skipping the string, which is the safe way to
    /// be wrong.
    private static func unescaped(_ character: Character) -> Character {
        switch character {
        case "n": "\n"
        case "t": "\t"
        case "r": "\r"
        case "0": "\0"
        default: character
        }
    }

    /// `%lld` is the specifier for an Int interpolation. Nothing in the source
    /// text carries a type, so this only orders the candidates — and so only
    /// steers which spelling a failure suggests. Lookup accepts either.
    private static func looksLikeInteger(_ expression: String) -> Bool {
        guard let integerHint else { return false }
        let range = NSRange(expression.startIndex..., in: expression)
        return integerHint.firstMatch(in: expression, range: range) != nil
    }

    /// `.count`, `count`, `itemCount` — but not the `count` inside `account`.
    private static let integerHint = try? NSRegularExpression(
        pattern: #"(?:^|[^A-Za-z])count\b|[a-z]Count\b"#)

    private static func startsLineComment(_ source: String, at index: String.Index) -> Bool {
        guard source[index] == "/" else { return false }
        let next = source.index(after: index)
        return next < source.endIndex && source[next] == "/"
    }

    private static func endOfLine(_ source: String, from index: String.Index) -> String.Index {
        var index = index
        while index < source.endIndex, source[index] != "\n" {
            index = source.index(after: index)
        }
        return index
    }
}

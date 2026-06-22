import Foundation

/// Fully-local, language-agnostic syntax highlighting for code and template
/// snippets. It returns token ranges only; the text is never copied or sent
/// anywhere. The macOS Library editor and the floating-panel preview share it,
/// so the tint is identical in both places.
///
/// The tokenizer is deliberately *structural* — string literals, line
/// comments, numbers, a small cross-language keyword set, and `{placeholder}`
/// template fields — rather than a per-language parser. That keeps it honest
/// about what it can know locally without shipping a grammar, and fast enough
/// to re-run on every keystroke. `{placeholder}` spans are highlighted as a
/// visual affordance; *filling* them in is a separate feature.
public enum GanchoSyntax {
    /// The kinds of span the tokenizer recognises.
    public enum TokenKind: String, Sendable, Equatable, CaseIterable {
        case keyword, string, comment, number, placeholder
    }

    /// A classified span, expressed as a `String.Index` range so callers can
    /// bridge to either `AttributedString` (SwiftUI) or `NSRange` (AppKit).
    public struct Token: Sendable, Equatable {
        public let range: Range<String.Index>
        public let kind: TokenKind

        public init(range: Range<String.Index>, kind: TokenKind) {
            self.range = range
            self.kind = kind
        }
    }

    /// A compact keyword set spanning Swift, JavaScript/TypeScript, Python,
    /// shell and SQL. Matching is case-sensitive: SQL keywords are recognised
    /// in their conventional uppercase form.
    static let keywords: Set<String> = [
        // Swift / C-family / JS / TS
        "func", "let", "var", "const", "class", "struct", "enum", "protocol",
        "extension", "guard", "return", "import", "if", "else", "for", "while",
        "switch", "case", "default", "in", "do", "try", "catch", "throw",
        "throws", "async", "await", "public", "private", "internal", "static",
        "self", "nil", "true", "false", "new", "function", "export",
        // Python
        "def", "elif", "lambda", "None", "True", "False", "and", "or", "not",
        // shell
        "echo", "fi", "then", "done",
        // SQL (uppercase by convention)
        "SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES", "UPDATE", "SET",
        "DELETE", "JOIN", "ORDER", "GROUP", "BY", "LIMIT",
    ]

    /// Tokenize `source` once, left to right; earlier matches win, so a keyword
    /// inside a comment or a number inside a string is not double-classified.
    public static func tokens(in source: String) -> [Token] {
        var tokens: [Token] = []
        var i = source.startIndex
        let end = source.endIndex

        func isIdentifier(_ c: Character) -> Bool { c == "_" || c.isLetter || c.isNumber }
        func lineEnd(from idx: String.Index) -> String.Index {
            source[idx...].firstIndex(of: "\n") ?? end
        }

        while i < end {
            let c = source[i]

            // Line comment: `//…` (but not the `//` in a `://` scheme) or a
            // `#…` that is the first non-blank on its line — so CSS `#fff`,
            // Swift `#available` and the like are not mistaken for comments.
            if c == "/" {
                let next = source.index(after: i)
                if next < end, source[next] == "/" {
                    let prevIsColon =
                        i > source.startIndex && source[source.index(before: i)] == ":"
                    if !prevIsColon {
                        let stop = lineEnd(from: i)
                        tokens.append(Token(range: i..<stop, kind: .comment))
                        i = stop
                        continue
                    }
                }
            }
            if c == "#", isFirstNonBlankOnLine(source, i) {
                let stop = lineEnd(from: i)
                tokens.append(Token(range: i..<stop, kind: .comment))
                i = stop
                continue
            }

            // String literal: "…" or '…', single line, honouring `\` escapes.
            if c == "\"" || c == "'" {
                var j = source.index(after: i)
                var closed = false
                while j < end {
                    let cj = source[j]
                    if cj == "\\" {
                        j = source.index(after: j)
                        if j < end { j = source.index(after: j) }
                        continue
                    }
                    if cj == "\n" { break }
                    if cj == c {
                        j = source.index(after: j)
                        closed = true
                        break
                    }
                    j = source.index(after: j)
                }
                let stop = closed ? j : lineEnd(from: i)
                tokens.append(Token(range: i..<stop, kind: .string))
                i = stop
                continue
            }

            // Template placeholder: `{field}` or `{field:default}` — non-empty,
            // no nested brace, and crucially NO internal whitespace, so code
            // braces like `{ return }` or `{ margin: 0 }` are left alone.
            // Highlight only; the fill-in flow lives elsewhere.
            if c == "{" {
                let afterBrace = source.index(after: i)
                if let close = source[afterBrace...].firstIndex(of: "}") {
                    let inner = source[afterBrace..<close]
                    if !inner.isEmpty, !inner.contains("{"),
                        !inner.contains(where: { $0 == " " || $0 == "\t" || $0 == "\n" })
                    {
                        let stop = source.index(after: close)
                        tokens.append(Token(range: i..<stop, kind: .placeholder))
                        i = stop
                        continue
                    }
                }
            }

            // Number: a digit run with an optional single fractional part.
            if c.isNumber {
                var j = source.index(after: i)
                while j < end, source[j].isNumber { j = source.index(after: j) }
                if j < end, source[j] == "." {
                    let afterDot = source.index(after: j)
                    if afterDot < end, source[afterDot].isNumber {
                        j = afterDot
                        while j < end, source[j].isNumber { j = source.index(after: j) }
                    }
                }
                tokens.append(Token(range: i..<j, kind: .number))
                i = j
                continue
            }

            // Identifier run — classified as a keyword only on an exact match.
            if c == "_" || c.isLetter {
                var j = source.index(after: i)
                while j < end, isIdentifier(source[j]) { j = source.index(after: j) }
                if keywords.contains(String(source[i..<j])) {
                    tokens.append(Token(range: i..<j, kind: .keyword))
                }
                i = j
                continue
            }

            i = source.index(after: i)
        }
        return tokens
    }

    /// Whether `idx` is the first non-whitespace character on its line.
    private static func isFirstNonBlankOnLine(_ s: String, _ idx: String.Index) -> Bool {
        var k = idx
        while k > s.startIndex {
            k = s.index(before: k)
            let c = s[k]
            if c == "\n" { return true }
            if c != " " && c != "\t" { return false }
        }
        return true
    }
}

import Testing

@testable import GanchoDesign

/// `GanchoSyntax` is the local highlighter shared by the panel preview and the
/// Library editor. These cover each token kind and the false positives the
/// structural approach is designed to avoid (`://`, `#fff`, keyword-as-substring).
@Suite("GanchoSyntax tokenizer")
struct SyntaxTests {
    /// (substring, kind) pairs, in document order — readable assertions.
    private func classified(_ source: String) -> [(text: String, kind: GanchoSyntax.TokenKind)] {
        GanchoSyntax.tokens(in: source).map { (String(source[$0.range]), $0.kind) }
    }

    private func kinds(_ source: String) -> [GanchoSyntax.TokenKind] {
        GanchoSyntax.tokens(in: source).map(\.kind)
    }

    // MARK: Keywords

    @Test("Keywords are tinted; surrounding identifiers are not")
    func keywords() {
        let tokens = classified("func greet() { return }")
        #expect(tokens.contains { $0.text == "func" && $0.kind == .keyword })
        #expect(tokens.contains { $0.text == "return" && $0.kind == .keyword })
        #expect(!tokens.contains { $0.text == "greet" })
    }

    @Test("Keyword matching is word-bounded, not substring (no false positives)")
    func keywordWordBoundary() {
        // "defunct" contains the substring "func"; "functions" contains
        // "function". A substring matcher would tint both — the tokenizer must
        // not, because each is a single identifier.
        #expect(kinds("defunct").isEmpty)
        #expect(kinds("functions").isEmpty)
    }

    @Test("SQL keywords match in their conventional uppercase form")
    func sqlKeywords() {
        let tokens = classified("SELECT id FROM clip")
        #expect(tokens.contains { $0.text == "SELECT" && $0.kind == .keyword })
        #expect(tokens.contains { $0.text == "FROM" && $0.kind == .keyword })
    }

    // MARK: Strings

    @Test("Double- and single-quoted strings are one token, escapes honoured")
    func strings() {
        #expect(
            classified(#"x = "hello world""#).contains {
                $0.text == "\"hello world\"" && $0.kind == .string
            })
        #expect(classified("c = 'a'").contains { $0.text == "'a'" && $0.kind == .string })
        // The escaped quote does not end the string early.
        #expect(classified(#""a\"b""#).contains { $0.text == #""a\"b""# && $0.kind == .string })
    }

    @Test("A number inside a string is not separately tinted")
    func numberInsideStringIsNotDoubleClassified() {
        #expect(kinds(#""42""#) == [.string])
    }

    // MARK: Comments

    @Test("// runs to end of line, but :// (a URL scheme) does not start one")
    func lineCommentsAndURLs() {
        #expect(
            classified("x = 1 // note").contains { $0.text == "// note" && $0.kind == .comment })
        #expect(!kinds("see https://example.com/path").contains(.comment))
    }

    @Test("# is a comment only as the first non-blank on its line")
    func hashComments() {
        #expect(classified("# heading").contains { $0.kind == .comment })
        #expect(classified("    # indented").contains { $0.kind == .comment })
        // Mid-line # (a CSS hex colour) is not a comment.
        #expect(!kinds("color: #fff").contains(.comment))
    }

    @Test("A keyword inside a comment is not separately tinted")
    func keywordInsideCommentIsNotDoubleClassified() {
        #expect(kinds("// func return").filter { $0 == .comment }.count == 1)
        #expect(!kinds("// func return").contains(.keyword))
    }

    // MARK: Numbers

    @Test("Integer and decimal runs are numbers; digits inside identifiers are not")
    func numbers() {
        #expect(classified("count = 42").contains { $0.text == "42" && $0.kind == .number })
        #expect(classified("pi = 3.14").contains { $0.text == "3.14" && $0.kind == .number })
        // "v2" is one identifier, not a number.
        #expect(!kinds("v2").contains(.number))
    }

    // MARK: Placeholders

    @Test("{field} is a placeholder; empty or multi-line braces are not")
    func placeholders() {
        #expect(
            classified("Hola {nombre}").contains {
                $0.text == "{nombre}" && $0.kind == .placeholder
            })
        #expect(
            classified("antes del {fecha:mañana}").contains {
                $0.text == "{fecha:mañana}" && $0.kind == .placeholder
            })
        #expect(!kinds("empty {}").contains(.placeholder))
        #expect(!kinds("{multi\nline}").contains(.placeholder))
        // Code braces contain whitespace and must not read as placeholders.
        #expect(!kinds("if x { return }").contains(.placeholder))
        #expect(!kinds("@layer base { * { margin: 0 } }").contains(.placeholder))
    }

    // MARK: Edges

    @Test("Empty input yields no tokens")
    func empty() {
        #expect(GanchoSyntax.tokens(in: "").isEmpty)
    }

    @Test("Every token's range bridges to a non-empty NSRange")
    func rangesBridge() {
        let source = "let url = \"https://x\" // {tag} 7"
        for token in GanchoSyntax.tokens(in: source) {
            #expect(!source[token.range].isEmpty)
        }
    }
}

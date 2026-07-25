import Testing

/// The localization sweep is only as wide as this scanner: every form pinned
/// here is one the old capture-group regex silently skipped, so a regression
/// would quietly stop checking real UI copy rather than fail loudly.
@Suite("Swift string-literal scanner")
struct SwiftLiteralScannerTests {
    /// Segments of the first literal in a snippet of Swift source.
    private func segments(of source: String) throws -> [SwiftLiteralSegment] {
        let quote = try #require(source.firstIndex(of: "\""))
        return try #require(SwiftLiteralScanner.scan(source, from: quote).segments)
    }

    @Test("An interpolated literal rebuilds the catalog key it resolves to")
    func interpolatedKey() throws {
        let scanned = try segments(of: #"Text("No clips for “\(query)”.")"#)
        #expect(SwiftLiteralScanner.localizedKeys(for: scanned).first == "No clips for “%@”.")
    }

    @Test("Both specifier spellings are offered, the likelier one first")
    func specifierCandidates() throws {
        let counted = try segments(of: #"Text("Paste stack, \(entries.count) items")"#)
        #expect(
            SwiftLiteralScanner.localizedKeys(for: counted)
                == ["Paste stack, %lld items", "Paste stack, %@ items"])
        let named = try segments(of: #"Text("Add to \(board.name)?")"#)
        #expect(SwiftLiteralScanner.localizedKeys(for: named) == ["Add to %@?", "Add to %lld?"])
    }

    @Test("A nested literal inside an interpolation does not end the scan early")
    func nestedLiteral() throws {
        let scanned = try segments(of: #"Text("\(Text("Waiting to sync")) · \(String(count))")"#)
        #expect(SwiftLiteralScanner.localizedKeys(for: scanned).first == "%@ · %lld")
    }

    @Test("Escapes decode into the characters a catalog key would hold")
    func escapes() throws {
        let scanned = try segments(of: #"Text("Say \"hi\" \n now")"#)
        #expect(SwiftLiteralScanner.localizedKeys(for: scanned) == ["Say \"hi\" \n now"])
    }

    @Test("A multiline block is skipped, and the scan resumes past it")
    func multilineBlock() throws {
        let source = "Text(\n    \"\"\"\n    Long copy.\n    \"\"\"\n)"
        let quote = try #require(source.firstIndex(of: "\""))
        let scanned = SwiftLiteralScanner.scan(source, from: quote)
        #expect(scanned.segments == nil)
        #expect(source[scanned.end...] == "\n)")
    }

    @Test("Past four interpolations the literal is left to a human")
    func interpolationCap() throws {
        let scanned = try segments(of: #"Text("\(a) \(b) \(c) \(d) \(e)")"#)
        #expect(SwiftLiteralScanner.localizedKeys(for: scanned).isEmpty)
    }

    @Test("A LocalizedStringKey body yields every literal, comments aside")
    func keyBodyLiterals() throws {
        let source = """
            private func bucketTitle(_ bucket: DateBucket) -> LocalizedStringKey {
                switch bucket {
                case .today: "Today"  // Not "Hoy" — that lives in the catalog.
                case .older: "Older"
                }
            }
            """
        let opened = try #require(source.firstIndex(of: "{"))
        let end = SwiftLiteralScanner.blockEnd(in: source, openedAt: opened, open: "{", close: "}")
        let literals = SwiftLiteralScanner.literals(
            in: source, range: source.index(after: opened)..<end)
        #expect(
            literals.compactMap { SwiftLiteralScanner.localizedKeys(for: $0).first }
                == ["Today", "Older"])
    }

    @Test("A brace inside a string literal does not close the body")
    func braceInsideLiteral() throws {
        let source = #"{ "a } b" }"#
        let opened = try #require(source.firstIndex(of: "{"))
        let end = SwiftLiteralScanner.blockEnd(in: source, openedAt: opened, open: "{", close: "}")
        #expect(source[end...] == "}")
    }

    @Test("Value composition is not copy, but interpolated prose is")
    func compositionIsNotCopy() throws {
        let composed = try segments(of: #"Label("\(recent.label): \(recent.preview)")"#)
        let composedKey = try #require(SwiftLiteralScanner.localizedKeys(for: composed).first)
        #expect(!LocalizationTests.isUserFacingCopy(composed, key: composedKey))

        let prose = try segments(of: #"Text("No clips for “\(query)”.")"#)
        let proseKey = try #require(SwiftLiteralScanner.localizedKeys(for: prose).first)
        #expect(LocalizationTests.isUserFacingCopy(prose, key: proseKey))
    }

    @Test("A lone Capitalized word is copy; a symbol name is not")
    func singleWordCopy() {
        #expect(LocalizationTests.isUserFacingCopy([.text("Share")], key: "Share"))
        #expect(!LocalizationTests.isUserFacingCopy([.text("delete.left")], key: "delete.left"))
    }
}

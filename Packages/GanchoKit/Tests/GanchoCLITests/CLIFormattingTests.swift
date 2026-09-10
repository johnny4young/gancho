import Foundation
import GanchoKit
import Testing

@testable import gancho

@Suite("gancho CLI — the decisions that had no test")
struct CLIFormattingTests {
    @Test("An unrecognized mode searches fuzzily rather than failing")
    func modeFallsBackToFuzzy() {
        #expect(CLIFormatting.mode("exact") == .exact)
        #expect(CLIFormatting.mode("REGEX") == .regex, "the option is case-insensitive")
        #expect(CLIFormatting.mode("fuzzy") == .fuzzy)
        // A typo should still search. Failing here would turn a slip into an
        // aborted command, which is worse than searching the default way.
        #expect(CLIFormatting.mode("exakt") == .fuzzy)
        #expect(CLIFormatting.mode(nil) == .fuzzy)
    }

    @Test("A summary never exceeds the width, ellipsis included")
    func summaryRespectsItsOwnWidth() {
        // Derived from the constant, so tuning the width moves the test with
        // it. The boundary is the point: the ellipsis REPLACES a character
        // rather than being appended past the limit.
        let width = CLIFormatting.summaryWidth
        for length in [width - 1, width, width + 1, width * 3] {
            let item = ClipItem(
                kind: .text, preview: String(repeating: "a", count: length),
                contentHash: "h")
            let line = CLIFormatting.oneLine(item)
            #expect(line.count <= width, "\(length) chars produced \(line.count)")
            if length > width {
                #expect(line.hasSuffix("…"), "a truncated summary must say so")
                #expect(line.count == width)
            } else {
                #expect(line.count == length, "a short summary must not be padded or cut")
            }
        }
    }

    @Test("A title wins over the preview, and newlines never break the column")
    func summaryPrefersTheTitleAndFlattens() {
        let titled = ClipItem(
            kind: .text, title: "Release notes", preview: "body", contentHash: "h")
        #expect(CLIFormatting.oneLine(titled) == "Release notes")

        let multiline = ClipItem(kind: .text, preview: "one\ntwo\nthree", contentHash: "h")
        #expect(CLIFormatting.oneLine(multiline) == "one two three")
        #expect(!CLIFormatting.oneLine(multiline).contains("\n"))
    }

    @Test("Nothing in a summary can move the cursor or open a column")
    func summaryFlattensEveryRowBreakingCharacter() {
        // The row is `id \t kind \t summary`, so a stray TAB opens a phantom
        // column and a bare CR returns the cursor to column 0 and overwrites
        // the id and kind already printed. CRLF is the case the old
        // `replacingOccurrences(of: "\n")` got actively WRONG rather than
        // merely missed: it replaced the LF and left the CR behind, which is
        // why it is listed separately from a lone CR here.
        let breakers: [(String, String)] = [
            ("LF", "\n"), ("CR", "\r"), ("CRLF", "\r\n"), ("NEL", "\u{85}"),
            ("LINE SEPARATOR", "\u{2028}"), ("PARAGRAPH SEPARATOR", "\u{2029}"),
            ("TAB", "\t"), ("ESC", "\u{1B}"), ("DEL", "\u{7F}")
        ]
        for (name, raw) in breakers {
            let item = ClipItem(kind: .text, preview: "one\(raw)two", contentHash: "h")
            let line = CLIFormatting.oneLine(item)
            #expect(line == "one two", "\(name) produced \(line.debugDescription)")
        }
    }

    @Test("Flattening leaves printable text alone, joined emoji included")
    func summaryKeepsPrintableText() {
        // Guards the choice of predicate: `CharacterSet.controlCharacters` is
        // Cc AND Cf, and Cf holds the zero-width joiner — using it would
        // collapse a whole family emoji into one space. Matching the `control`
        // general category instead keeps it.
        let item = ClipItem(kind: .text, preview: "héllo 👨‍👩‍👧 🎉 ok", contentHash: "h")
        #expect(CLIFormatting.oneLine(item) == "héllo 👨‍👩‍👧 🎉 ok")
    }

    @Test("JSON output is stable enough to diff and parse")
    func jsonIsSortedAndISO8601() throws {
        struct Row: Encodable {
            let zebra: String
            let alpha: String
            let at: Date
        }
        let data = try CLIFormatting.encodePretty(
            Row(zebra: "z", alpha: "a", at: Date(timeIntervalSince1970: 0)))
        let text = try #require(String(data: data, encoding: .utf8))

        let alphaAt = try #require(text.range(of: "\"alpha\""))
        let zebraAt = try #require(text.range(of: "\"zebra\""))
        #expect(alphaAt.lowerBound < zebraAt.lowerBound, "keys must sort, so runs diff cleanly")
        #expect(text.contains("1970-01-01T00:00:00Z"), "dates must be ISO-8601, not a number")
    }

    @Test("A blank store-dir override is ignored, not treated as a path")
    func blankOverrideDoesNotRedirectTheStore() {
        // An exported-but-empty variable is a shell accident. Honoring it
        // would NOT select the filesystem root: `URL(fileURLWithPath: "")`
        // resolves against the process's current working directory, so the CLI
        // would read a store from wherever it happened to be run, find none,
        // and look like an empty clipboard.
        let real = CLIFormatting.storeDirectory(environment: [:])
        #expect(CLIFormatting.storeDirectory(environment: ["GANCHO_STORE_DIR": ""]) == real)
        #expect(CLIFormatting.storeDirectory(environment: ["GANCHO_STORE_DIR": "   "]) == real)

        let override = CLIFormatting.storeDirectory(
            environment: ["GANCHO_STORE_DIR": "/tmp/gancho-test"])
        #expect(override.path == "/tmp/gancho-test")
        #expect(override != real)
    }
}

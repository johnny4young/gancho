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
        // An exported-but-empty variable is a shell accident. Honoring it would
        // send the CLI to the filesystem root instead of the user's history —
        // it would find no store and look like an empty clipboard.
        let real = CLIFormatting.storeDirectory(environment: [:])
        #expect(CLIFormatting.storeDirectory(environment: ["GANCHO_STORE_DIR": ""]) == real)
        #expect(CLIFormatting.storeDirectory(environment: ["GANCHO_STORE_DIR": "   "]) == real)

        let override = CLIFormatting.storeDirectory(
            environment: ["GANCHO_STORE_DIR": "/tmp/gancho-test"])
        #expect(override.path == "/tmp/gancho-test")
        #expect(override != real)
    }
}

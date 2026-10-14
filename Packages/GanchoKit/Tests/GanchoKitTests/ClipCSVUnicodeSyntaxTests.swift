import Foundation
import Testing

@testable import GanchoKit

@Suite("CSV syntax and Unicode content")
struct ClipCSVUnicodeSyntaxTests {
    @Test("CRLF record separators produce each candidate")
    func crlfRecords() throws {
        let csv = "text,title,pinned\r\nalpha,Note,true\r\nbeta,Other,false\r\n"
        let document = try ClipImporter.readCSV(Data(csv.utf8))
        #expect(
            document.candidates == [
                .init(text: "alpha", title: "Note", isPinned: true),
                .init(text: "beta", title: "Other")
            ])
        #expect(document.unsupportedCount == 0)
    }

    @Test("Combining marks after delimiters belong to the following field")
    func delimiterBeforeCombiningMark() throws {
        let csv = "text,title\nalpha,\u{0301}beta\n"
        let document = try ClipImporter.readCSV(Data(csv.utf8))
        #expect(document.candidates == [.init(text: "alpha", title: "\u{0301}beta")])
        #expect(document.unsupportedCount == 0)
    }

    @Test("Quoted fields and escaped quotes preserve following combining marks")
    func quotesBeforeCombiningMarks() throws {
        let csv = "text,title\n\"\u{0301}first,\"\"\u{0301}quoted\"\"\",Note\n"
        let document = try ClipImporter.readCSV(Data(csv.utf8))
        #expect(
            document.candidates == [
                .init(text: "\u{0301}first,\"\u{0301}quoted\"", title: "Note")
            ])
        #expect(document.unsupportedCount == 0)
    }

    @Test("Exports quote CRLF and CR inside fields")
    func quotesCarriageReturns() {
        #expect(ClipExporter.csvEscape("first\r\nsecond") == "\"first\r\nsecond\"")
        #expect(ClipExporter.csvEscape("first\rsecond") == "\"first\rsecond\"")
        #expect(ClipExporter.csvEscape("\r\n=fixture") == "\"'\r\n=fixture\"")
    }

    @Test("Exports quote and escape syntax followed by combining marks")
    func escapesSyntaxBeforeCombiningMarks() {
        #expect(ClipExporter.csvEscape("left,\u{0301}right") == "\"left,\u{0301}right\"")
        #expect(ClipExporter.csvEscape("left\"\u{0301}right") == "\"left\"\"\u{0301}right\"")
        #expect(ClipExporter.csvEscape("=\u{0301}fixture") == "'=\u{0301}fixture")
    }

    @Test("CSV exports preserve exact Unicode bytes when reimported")
    func exportRoundTrips() throws {
        for text in [
            "first\r\nsecond", "first\rsecond", "\r\n=fixture", "\u{0301}fixture",
            "left,\u{0301}right", "left\"\u{0301}right", "=\u{0301}fixture",
            "'\u{0301}fixture"
        ] {
            var row = ClipRow(item: ClipItem(preview: "synthetic", contentHash: "synthetic"))
            row.contentText = text
            let csv = ClipExporter.csvHeader + ClipExporter.csvLine(for: row)
            let document = try ClipImporter.readCSV(Data(csv.utf8))
            let candidate = try #require(document.candidates.first)
            #expect(document.candidates.count == 1)
            #expect(Array(candidate.text.utf8) == Array(text.utf8))
            #expect(document.unsupportedCount == 0)
        }
    }
}

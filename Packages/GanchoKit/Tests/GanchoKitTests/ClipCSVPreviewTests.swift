import Foundation
import Testing

@testable import GanchoKit

@Suite("CSV preview projection")
struct ClipCSVPreviewTests {
    @Test("BOM and normalized headers keep column precedence and formula-guard policy")
    func exportHeader() throws {
        let csv =
            "\u{feff}contentText, TEXT ,title,title,isPinned\nignored,'=sum,'@first,second,YES"
        let document = try ClipImporter.readCSV(Data(csv.utf8))
        #expect(
            document.candidates == [.init(text: "=sum", title: "@first", isPinned: true)])
        #expect(document.unsupportedCount == 0)
    }

    @Test("Foreign text columns preserve literal apostrophes")
    func foreignFormulaText() throws {
        let document = try ClipImporter.readCSV(Data("text,title,pinned\n'=literal,'@title,1".utf8))
        #expect(
            document.candidates == [.init(text: "'=literal", title: "'@title", isPinned: true)])
    }

    @Test("Quoted multiline and escaped quotes survive row-at-a-time projection")
    func quotedFields() throws {
        let csv = "text,title\n\"first\r\nsecond,\"\"quoted\"\"\",\"  Note  \"\n\n"
        let document = try ClipImporter.readCSV(Data(csv.utf8))
        #expect(document.candidates == [.init(text: "first\r\nsecond,\"quoted\"", title: "Note")])
        #expect(document.unsupportedCount == 0)
    }

    @Test("Short optional fields and unsupported text rows keep their counts")
    func shortRows() throws {
        let csv = "title,text,pinned\nOnly title\nBlank,   ,true\nNote,body\n,other,no"
        let document = try ClipImporter.readCSV(Data(csv.utf8))
        #expect(document.candidates == [.init(text: "body", title: "Note"), .init(text: "other")])
        #expect(document.unsupportedCount == 2)
    }

    @Test("Malformed tails expose no document and keep syntax-error precedence")
    func malformedTail() {
        for header in ["text", "unrecognized"] {
            #expect(throws: ClipImporter.ImportError.unreadable(.unclosedQuotedField)) {
                _ = try ClipImporter.readCSV(Data("\(header)\nvalid\n\"unfinished".utf8))
            }
        }
        #expect(throws: ClipImporter.ImportError.unreadable(.emptyCSV)) {
            _ = try ClipImporter.readCSV(Data("\u{feff}\n\n".utf8))
        }
    }

    @Test("Large previews keep candidate order and repeatable isolated state")
    func largePreview() throws {
        let count = 5_000
        let rows = (0..<count).map { "row-\($0),Title \($0),\($0.isMultiple(of: 2))" }
        let data = Data((["text,title,pinned"] + rows).joined(separator: "\n").utf8)
        let document = try ClipImporter.readCSV(data)
        let expected = (0..<count).map {
            ClipImporter.Candidate(
                text: "row-\($0)", title: "Title \($0)", isPinned: $0.isMultiple(of: 2))
        }
        #expect(document.candidates == expected)
        #expect(document.unsupportedCount == 0)
        #expect(try ClipImporter.readCSV(data) == document)
    }
}

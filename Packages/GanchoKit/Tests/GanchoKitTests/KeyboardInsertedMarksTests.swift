import Foundation
import Testing

@testable import GanchoKit

@Suite("Keyboard inserted marks")
struct KeyboardInsertedMarksTests {
    @Test("every row typed into the same document stays marked")
    func marksAccumulateInOneDocument() {
        let document = UUID()
        let first = UUID()
        let second = UUID()
        var marks = KeyboardInsertedMarks()

        marks.markInserted(first, into: document)
        marks.markInserted(second, into: document)
        marks.observe(document: document)

        #expect(marks.ids == [first, second])
    }

    @Test("a new document clears the marks")
    func documentChangeClears() {
        let row = UUID()
        var marks = KeyboardInsertedMarks()
        marks.markInserted(row, into: UUID())

        marks.observe(document: UUID())

        #expect(!marks.contains(row))
        #expect(marks.ids.isEmpty)
    }

    @Test("inserting into another document keeps only the new row")
    func insertIntoAnotherDocument() {
        let old = UUID()
        let new = UUID()
        var marks = KeyboardInsertedMarks()
        marks.markInserted(old, into: UUID())

        marks.markInserted(new, into: UUID())

        #expect(marks.ids == [new])
    }

    @Test("text and file paths reach the field; an image does not")
    func fieldText() {
        #expect(KeyboardInsertedMarks.fieldText(for: .text("hola")) == "hola")
        #expect(
            KeyboardInsertedMarks.fieldText(for: .fileReferences(["/a.txt", "/b.txt"]))
                == "/a.txt\n/b.txt")
        #expect(
            KeyboardInsertedMarks.fieldText(
                for: .binary(data: Data([0x89]), typeIdentifier: "public.png")) == nil)
    }
}

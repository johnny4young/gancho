import CryptoKit
import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("Snippet templates")
struct SnippetTemplateTests {
    @Test("Fields parse with defaults, dedupe, and order")
    func fieldParsing() {
        let fields = SnippetTemplate.fields(
            in: "Hi {name:World}, your {thing} is ready. Bye {name:World}!")
        #expect(fields.map(\.name) == ["name", "thing"])
        #expect(fields[0].defaultValue == "World")
        #expect(fields[1].defaultValue == nil)
        #expect(SnippetTemplate.isTemplate("plain text") == false)
    }

    @Test("Fill applies values everywhere, defaults fill the gaps")
    func filling() {
        let template = "Hi {name:World}, {greeting} {name:World}. Count: {n}"
        let filled = SnippetTemplate.fill(template, values: ["greeting": "hola"])
        #expect(filled == "Hi World, hola World. Count: ")
        let full = SnippetTemplate.fill(
            template, values: ["name": "Ana", "greeting": "q", "n": "3"])
        #expect(full == "Hi Ana, q Ana. Count: 3")
    }
}

@Suite("Importers")
struct ClipImporterTests {
    @Test("CSV preview decodes quotes/newlines and reports unsupported rows")
    func csv() throws {
        let csv = """
            text,title,pinned
            "hello, world",Greeting,true
            "multi
            line",,false
            ,Missing,false
            """
        let document = try ClipImporter.readCSV(Data(csv.utf8))
        #expect(document.candidates.count == 2)
        #expect(document.unsupportedCount == 1)
        #expect(
            document.candidates[0] == .init(text: "hello, world", title: "Greeting", isPinned: true)
        )
        #expect(document.candidates[1].text == "multi\nline")
    }

    @Test("Bad CSV throws a typed error")
    func badCSV() {
        #expect(throws: ClipImporter.ImportError.unreadable(.missingTextColumn)) {
            _ = try ClipImporter.readCSV(Data("nope,really\n1,2".utf8))
        }
        #expect(throws: ClipImporter.ImportError.unreadable(.unclosedQuotedField)) {
            _ = try ClipImporter.readCSV(Data("text\n\"unfinished".utf8))
        }
    }

    @Test("Maccy preview is read-only and counts unsupported representations")
    func maccy() async throws {
        // Synthesize Maccy's Core Data shape.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("maccy-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let dbURL = dir.appendingPathComponent("Storage.sqlite")
        let source = try DatabaseQueue(path: dbURL.path)
        try await source.write { db in
            try db.execute(
                sql: "CREATE TABLE ZHISTORYITEMCONTENT (ZTYPE TEXT, ZVALUE BLOB)")
            try db.execute(
                sql: "INSERT INTO ZHISTORYITEMCONTENT VALUES ('public.utf8-plain-text', ?)",
                arguments: [Data("from maccy".utf8)])
            try db.execute(
                sql: "INSERT INTO ZHISTORYITEMCONTENT VALUES ('public.tiff', ?)",
                arguments: [Data([1, 2])])
        }

        let hashBefore = try fileHash(dbURL)
        let document = try await ClipImporter.readMaccy(databaseAt: dbURL)
        let hashAfter = try fileHash(dbURL)
        #expect(document.candidates == [.init(text: "from maccy")])
        #expect(document.unsupportedCount == 1)
        #expect(hashAfter == hashBefore)
    }

    @Test("Corrupt Maccy source returns a stable content-free reason")
    func corruptMaccy() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("corrupt-\(UUID().uuidString).sqlite")
        try Data("not sqlite".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        await #expect(throws: ClipImporter.ImportError.self) {
            _ = try await ClipImporter.readMaccy(databaseAt: url)
        }
    }

    @Test("Cancelling a Maccy preview preserves task cancellation")
    func cancelledMaccy() async throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cancelled-\(UUID().uuidString).sqlite")
        let source = try DatabaseQueue(path: url.path)
        try await source.write { database in
            try database.execute(
                sql: "CREATE TABLE ZHISTORYITEMCONTENT (ZTYPE TEXT, ZVALUE BLOB)")
        }
        defer { try? FileManager.default.removeItem(at: url) }
        let gate = ImportCancellationGate()
        let task = Task {
            await gate.wait()
            return try await ClipImporter.readMaccy(databaseAt: url)
        }
        await gate.waitUntilBlocked()
        task.cancel()
        await gate.open()

        await #expect(throws: CancellationError.self) {
            _ = try await task.value
        }
    }

    private func fileHash(_ url: URL) throws -> String {
        SHA256.hash(data: try Data(contentsOf: url))
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

private actor ImportCancellationGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var blockedContinuation: CheckedContinuation<Void, Never>?

    func wait() async {
        blockedContinuation?.resume()
        blockedContinuation = nil
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilBlocked() async {
        guard continuation == nil else { return }
        await withCheckedContinuation { blockedContinuation = $0 }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}

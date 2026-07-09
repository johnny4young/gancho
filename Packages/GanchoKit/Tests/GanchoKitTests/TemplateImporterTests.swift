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
    private func makeStore() throws -> GRDBClipboardStore {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("imp-\(UUID().uuidString)")))
        try store.migrate()
        return store
    }

    @Test("CSV imports with quotes/newlines, dedupes, flags pins")
    func csv() async throws {
        let store = try makeStore()
        let csv = """
            text,title,pinned
            "hello, world",Greeting,true
            "multi
            line",,false
            "hello, world",Greeting,true
            """
        let summary = try await ClipImporter.importCSV(Data(csv.utf8), into: store)
        #expect(summary.imported == 2)
        #expect(summary.skippedDuplicates == 1)
        let items = try await store.items()
        #expect(items.contains { $0.preview == "hello, world" && $0.isPinned })
    }

    @Test("Bad CSV throws a typed error")
    func badCSV() async throws {
        let store = try makeStore()
        await #expect(throws: ClipImporter.ImportError.self) {
            _ = try await ClipImporter.importCSV(Data("nope,really\n1,2".utf8), into: store)
        }
    }

    @Test("Maccy import reads a synthesized source database read-only")
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

        let store = try makeStore()
        let summary = try await ClipImporter.importMaccy(databaseAt: dbURL, into: store)
        #expect(summary.imported == 1)
        #expect(try await store.items().first?.preview == "from maccy")
    }
}

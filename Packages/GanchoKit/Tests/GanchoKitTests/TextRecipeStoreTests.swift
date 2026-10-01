import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

@Suite("Local recipe persistence")
struct TextRecipeStoreTests {
    private func store(_ writer: any DatabaseWriter) throws -> GRDBClipboardStore {
        let store = GRDBClipboardStore(
            writer: writer,
            blobs: BlobStore(
                directory: FileManager.default.temporaryDirectory.appendingPathComponent(
                    "recipes-\(UUID())")))
        try store.migrate()
        return store
    }
    @Test func presetsSeedOnceAndDeletionNeverAffectsClips() async throws {
        let writer = try DatabaseQueue()
        let store = try store(writer)
        #expect(try await store.textRecipes().compactMap(\.recipe) == TextRecipePresets.all)
        let clip = ClipItem(contentHash: "synthetic")
        try await store.insert(clip, content: .text("Synthetic"))
        let id = TextRecipePresets.all[0].id.uuidString
        try await store.deleteTextRecipe(id: id)
        try store.migrate()
        #expect(try await store.textRecipes().count == 2)
        #expect(try await store.item(id: clip.id) != nil)
    }
    @Test func reopeningEncryptedStorePreservesEditedDefinitions() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "recipe-restart-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let path = directory.appendingPathComponent("recipes.sqlite").path
        var configuration = Configuration()
        configuration.prepareDatabase { try $0.usePassphrase("synthetic-test-key") }
        var recipe = TextRecipe(
            name: "Unicode mañana", steps: [TextActionStep(actionID: TextActionCatalog.trimLines)])
        do {
            let first = try store(DatabaseQueue(path: path, configuration: configuration))
            try await first.saveTextRecipe(recipe)
            recipe.name = "Renamed mañana"
            recipe.steps.append(TextActionStep(actionID: TextActionCatalog.normalizeNewlines))
            recipe.steps.reverse()
            try await first.saveTextRecipe(recipe)
            #expect(try await first.textRecipes().count == 4)
        }
        let second = try store(DatabaseQueue(path: path, configuration: configuration))
        #expect(try await second.textRecipes().contains { $0.recipe == recipe })
    }
    @Test func corruptAndFutureDefinitionsRemainIsolatedAndPreserved() async throws {
        let store = try store(DatabaseQueue())
        let future = TextRecipe(
            version: 99, name: "Future", steps: [TextActionStep(actionID: "future")])
        let data = try JSONEncoder().encode(future)
        try await store.writer.write { db in
            try db.execute(
                sql: "INSERT INTO text_recipe VALUES (?, ?)", arguments: ["bad-id", Data([0, 1])])
            try db.execute(
                sql: "INSERT INTO text_recipe VALUES (?, ?)",
                arguments: [future.id.uuidString, data])
        }
        let records = try await store.textRecipes()
        #expect(records.count == 5)
        #expect(records.first { $0.id == "bad-id" }?.recipe == nil)
        #expect(records.first { $0.id == future.id.uuidString }?.recipe == future)
        await #expect(throws: TextRecipeError.unsupportedVersion) {
            try await store.saveTextRecipe(future)
        }
        let preserved = try await store.writer.read { db in
            try Data.fetchOne(
                db, sql: "SELECT definition FROM text_recipe WHERE id = ?",
                arguments: [future.id.uuidString])
        }
        #expect(preserved == data)
    }
    @Test func oversizedDefinitionsAreIsolatedBeforeDecodingAndNeverWritten() async throws {
        let store = try store(DatabaseQueue())
        try await store.writer.write { db in
            try db.execute(
                sql: "INSERT INTO text_recipe VALUES (?, ?)",
                arguments: ["oversized", Data(repeating: 65, count: 65_537)])
        }
        let records = try await store.textRecipes()
        #expect(records.count == 4)
        #expect(records.first { $0.id == "oversized" }?.recipe == nil)
        let giantName = "a" + String(repeating: "\u{0301}", count: 40_000)
        let recipe = TextRecipe(
            name: giantName,
            steps: [TextActionStep(actionID: TextActionCatalog.trimLines)])
        await #expect(throws: TextRecipeError.tooLarge) { try await store.saveTextRecipe(recipe) }
        #expect(try await store.textRecipes().count == 4)
    }

}

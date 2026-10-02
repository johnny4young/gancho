import Foundation
import GRDB

public struct StoredTextRecipe: Identifiable, Sendable, Equatable {
    public let id: String
    public let recipe: TextRecipe?
    public init(id: String, recipe: TextRecipe?) {
        self.id = id
        self.recipe = recipe
    }
}

public protocol TextRecipeStoring: Sendable {
    func textRecipes() async throws -> [StoredTextRecipe]
    func saveTextRecipe(_ recipe: TextRecipe) async throws
    func deleteTextRecipe(id: String) async throws
}

public enum TextRecipePresets {
    public static let all: [TextRecipe] = [
        preset(
            1, "Clean OCR", [TextActionCatalog.normalizeNewlines, TextActionCatalog.trimLineEnds]),
        preset(2, "Clean list", [TextActionCatalog.trimLines, "transform.dedupeLines"]),
        preset(
            3, "Prepare redacted context",
            [TextActionCatalog.redactPII, TextActionCatalog.formatContext])
    ]
    private static func preset(_ number: UInt8, _ name: String, _ actions: [String]) -> TextRecipe {
        let id = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, number))
        let steps = actions.enumerated().map { index, action in
            TextActionStep(
                id: UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, number, 0, UInt8(index))),
                actionID: action)
        }
        return TextRecipe(id: id, name: name, steps: steps)
    }
}

extension GRDBClipboardStore: TextRecipeStoring {
    public func textRecipes() async throws -> [StoredTextRecipe] {
        try Task.checkCancellation()
        let records = try await writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT id, CASE WHEN LENGTH(definition) <= 65536 THEN definition ELSE NULL END AS definition
                    FROM text_recipe ORDER BY rowid
                    """
            ).map {
                row in
                let id: String = row["id"]
                let data: Data? = row["definition"]
                let decoded = data.flatMap { try? JSONDecoder().decode(TextRecipe.self, from: $0) }
                return StoredTextRecipe(
                    id: id, recipe: decoded?.id.uuidString == id ? decoded : nil)
            }
        }
        try Task.checkCancellation()
        return records
    }
    public func saveTextRecipe(_ recipe: TextRecipe) async throws {
        try Task.checkCancellation()
        var normalized = recipe
        normalized.name = recipe.name.trimmingCharacters(in: .whitespacesAndNewlines)
        let recipe = normalized
        try recipe.validate()
        let data = try JSONEncoder().encode(recipe)
        guard data.count <= 65_536 else { throw TextRecipeError.tooLarge }
        try await writer.write { db in
            try Task.checkCancellation()
            try db.execute(
                sql: """
                    INSERT INTO text_recipe (id, definition) VALUES (?, ?)
                    ON CONFLICT (id) DO UPDATE SET definition = excluded.definition
                    """, arguments: [recipe.id.uuidString, data])
        }
    }
    public func deleteTextRecipe(id: String) async throws {
        try Task.checkCancellation()
        try await writer.write { db in
            try Task.checkCancellation()
            try db.execute(sql: "DELETE FROM text_recipe WHERE id = ?", arguments: [id])
        }
    }
}

import Foundation
import GanchoAI
import GanchoKit
import Testing

@testable import GanchoAppCore

@Suite("Bounded deterministic recipes")
struct TextRecipeTests {
    private func recipe(_ ids: [String]) -> TextRecipe {
        TextRecipe(name: "Synthetic recipe", steps: ids.map { TextActionStep(actionID: $0) })
    }

    @Test(arguments: PasteTransform.allCases)
    func existingTransformsRemainEquivalent(_ transform: PasteTransform) async throws {
        let input = " z\r\nß mañana\n z\n"
        let output = try await TextRecipeExecutor().run(
            recipe(["transform.\(transform.rawValue)"]), on: input)
        #expect(output == transform.apply(to: input))
    }

    @Test func ocrCleaningPreservesIndentationParagraphsAndHyphens() async throws {
        let input = "  indented \t\r\n\r\nword-\r\ncontinuation  \n"
        let cleaned = try await TextRecipeExecutor().run(
            recipe([TextActionCatalog.normalizeNewlines, TextActionCatalog.trimLineEnds]), on: input
        )
        #expect(cleaned == "  indented\n\nword-\ncontinuation\n")
    }

    @Test func listCleaningKeepsFirstOccurrenceAndNeverSortsImplicitly() async throws {
        let cleaned = try await TextRecipeExecutor().run(
            recipe([TextActionCatalog.trimLines, "transform.dedupeLines"]),
            on: " z \r\n a\n z \nmañana\na")
        #expect(cleaned == "z\na\nmañana")
        let sorted = try await TextRecipeExecutor().run(
            recipe([TextActionCatalog.trimLines, "transform.dedupeLines", "transform.sortLines"]),
            on: " z \n a\n z")
        #expect(sorted == "a\nz")
    }

    @Test func redactionPrecedesLiteralContextFormatting() async throws {
        let input = "Email test@example.com. <script>not executable</script>"
        let output = try await TextRecipeExecutor().run(
            recipe([TextActionCatalog.redactPII, TextActionCatalog.formatContext]), on: input)
        let id = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
        let expected = try SelectedContextFormatter.format([
            CombinedTextPart(id: id, content: .text(PIIRedactor.redact(input)))
        ])
        #expect(output == expected.markdown)
        #expect(!output.contains("test@example.com"))
    }

    @Test func unknownActionsVersionsAndParametersArePreservedButNeverRun() throws {
        let unsupported = TextRecipe(
            name: "Future",
            steps: [
                TextActionStep(
                    actionID: "future.action", version: 3, parameters: ["future": "value"])
            ])
        let encoded = try JSONEncoder().encode(unsupported)
        let decoded = try JSONDecoder().decode(TextRecipe.self, from: encoded)
        #expect(decoded == unsupported)
        #expect(throws: TextRecipeError.unsupportedVersion) { try decoded.validate() }
        #expect(throws: TextRecipeError.unknownAction) { try recipe(["unknown"]).validate() }
        let invalid = TextRecipe(
            name: "Invalid",
            steps: [
                TextActionStep(
                    actionID: "transform.lowercase", parameters: ["script": "never executed"])
            ])
        #expect(throws: TextRecipeError.invalidParameters) { try invalid.validate() }
        #expect(throws: TextRecipeError.invalidDefinition) {
            try recipe(Array(repeating: "transform.plainText", count: 9)).validate()
        }
        try recipe(Array(repeating: "transform.plainText", count: 8)).validate()
        let steps = [TextActionStep(actionID: "transform.plainText")]
        let padded = "  " + String(repeating: "n", count: TextRecipe.maximumNameLength) + "  "
        try TextRecipe(name: padded, steps: steps).validate()
        #expect(throws: TextRecipeError.invalidDefinition) {
            try TextRecipe(name: padded + "n", steps: steps).validate()
        }
        #expect(throws: TextRecipeError.unsupportedVersion) {
            try TextRecipe(
                name: "Old", steps: [TextActionStep(actionID: "transform.plainText", version: 2)]
            ).validate()
        }
    }

    @Test func byteLimitsRejectInputsIntermediateExpansionAndContextHeaders() async throws {
        let limit = TextRecipeExecutor.maximumUTF8Bytes
        #expect(
            try await TextRecipeExecutor().run(
                recipe(["transform.plainText"]), on: String(repeating: "a", count: limit)
            ).utf8.count == limit)
        await #expect(throws: TextRecipeError.tooLarge) {
            try await TextRecipeExecutor().run(
                recipe(["transform.plainText"]), on: String(repeating: "a", count: limit) + "🌿")
        }
        await #expect(throws: TextRecipeError.tooLarge) {
            try await TextRecipeExecutor().run(
                recipe(["transform.urlEncode", "transform.sha256Hex"]),
                on: String(repeating: " ", count: limit))
        }
        await #expect(throws: SelectedContextError.tooLarge) {
            try await TextRecipeExecutor().run(
                recipe([TextActionCatalog.formatContext]),
                on: String(repeating: "a", count: SelectedContextFormatter.maximumUTF8Bytes))
        }
    }
    @Test func cancellationBeforeAdmissionNeverProducesAResult() async throws {
        let gate = RecipeAdmissionGate()
        let task = Task {
            await gate.wait()
            return try await TextRecipeExecutor().run(
                recipe([TextActionCatalog.normalizeNewlines]), on: "synthetic\r\ntext")
        }
        await gate.admitted()
        task.cancel()
        await gate.release()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

}

private actor RecipeAdmissionGate {
    private var continuation: CheckedContinuation<Void, Never>?
    private var observer: CheckedContinuation<Void, Never>?
    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
            observer?.resume()
            observer = nil
        }
    }
    func admitted() async {
        if continuation != nil { return }
        await withCheckedContinuation { observer = $0 }
    }
    func release() {
        continuation?.resume()
        continuation = nil
    }
}

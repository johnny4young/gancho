import Foundation
import GanchoAI
import GanchoKit

/// Deterministic execution only. No stores, UI, pasteboards, model sessions or scripts.
public struct TextRecipeExecutor: Sendable {
    public static let maximumUTF8Bytes = 1_048_576
    public init() {}

    public func run(_ recipe: TextRecipe, on text: String) async throws -> String {
        try Task.checkCancellation()
        try recipe.validate()
        guard text.utf8.count <= Self.maximumUTF8Bytes else { throw TextRecipeError.tooLarge }
        let worker = Task.detached(priority: .userInitiated) { try Self.apply(recipe, to: text) }
        return try await withTaskCancellationHandler {
            let output = try await worker.value
            try Task.checkCancellation()
            return output
        } onCancel: {
            worker.cancel()
        }
    }

    private static func apply(_ recipe: TextRecipe, to text: String) throws -> String {
        var output = text
        for step in recipe.steps {
            try Task.checkCancellation()
            output = try apply(step, to: output)
            guard output.utf8.count <= maximumUTF8Bytes else { throw TextRecipeError.tooLarge }
            try Task.checkCancellation()
        }
        return output
    }

    private static func apply(_ step: TextActionStep, to text: String) throws -> String {
        if step.actionID.hasPrefix("transform."),
            let transform = PasteTransform(
                rawValue: String(step.actionID.dropFirst("transform.".count)))
        {
            return transform.apply(to: text)
        }
        switch step.actionID {
        case TextActionCatalog.normalizeNewlines:
            var output = ""
            output.reserveCapacity(text.utf8.count)
            for (index, character) in text.enumerated() {
                if index.isMultiple(of: 4096) { try Task.checkCancellation() }
                output.append(character.isNewline ? "\n" : character)
            }
            return output
        case TextActionCatalog.trimLineEnds:
            return try transformLines(text) { line in
                var trimmed = line
                while let last = trimmed.last, last.isWhitespace { trimmed.removeLast() }
                return trimmed
            }
        case TextActionCatalog.trimLines:
            return try transformLines(text) { $0.trimmingCharacters(in: .whitespaces) }
        case TextActionCatalog.redactPII: return PIIRedactor.redact(text)
        case TextActionCatalog.formatContext:
            let id = UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0))
            return try SelectedContextFormatter.format([
                CombinedTextPart(id: id, content: .text(text))
            ]).markdown
        default: throw TextRecipeError.unknownAction
        }
    }

    private static func transformLines(
        _ text: String, transform: (String) -> String
    ) throws -> String {
        var output = ""
        var line = ""
        output.reserveCapacity(text.utf8.count)
        for (index, character) in text.enumerated() {
            if index.isMultiple(of: 4096) { try Task.checkCancellation() }
            if character.isNewline {
                output += transform(line)
                output.append(character)
                line.removeAll(keepingCapacity: true)
            } else {
                line.append(character)
            }
        }
        output += transform(line)
        return output
    }
}

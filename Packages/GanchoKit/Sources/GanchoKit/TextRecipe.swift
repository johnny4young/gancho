import Foundation

public enum TextRecipeError: Error, Equatable {
    case unsupportedVersion, unknownAction, invalidParameters, invalidDefinition, tooLarge
}

public struct TextActionDescriptor: Identifiable, Sendable, Equatable {
    public let id: String
    public let version: Int
    public let title: String
}

public struct TextActionStep: Codable, Sendable, Equatable, Identifiable {
    public var id: UUID
    public var actionID: String
    public var version: Int
    public var parameters: [String: String]

    public init(
        id: UUID = UUID(), actionID: String, version: Int = 1, parameters: [String: String] = [:]
    ) {
        self.id = id
        self.actionID = actionID
        self.version = version
        self.parameters = parameters
    }

    public func validate() throws {
        guard let descriptor = TextActionCatalog.descriptors.first(where: { $0.id == actionID })
        else {
            guard version == 1 else { throw TextRecipeError.unsupportedVersion }
            throw TextRecipeError.unknownAction
        }
        guard version == descriptor.version else { throw TextRecipeError.unsupportedVersion }
        guard parameters.isEmpty else { throw TextRecipeError.invalidParameters }
    }
}

public enum TextActionCatalog {
    public static let normalizeNewlines = "normalize-newlines"
    public static let trimLineEnds = "trim-line-ends"
    public static let trimLines = "trim-lines"
    public static let redactPII = "redact-pii"
    public static let formatContext = "format-context"

    public static let descriptors: [TextActionDescriptor] =
        PasteTransform.allCases.map {
            TextActionDescriptor(id: "transform.\($0.rawValue)", version: 1, title: $0.title)
        } + [
            TextActionDescriptor(
                id: normalizeNewlines, version: 1, title: "Normalize line endings"),
            TextActionDescriptor(id: trimLineEnds, version: 1, title: "Trim trailing line spaces"),
            TextActionDescriptor(id: trimLines, version: 1, title: "Trim each line"),
            TextActionDescriptor(id: redactPII, version: 1, title: "Redact PII"),
            TextActionDescriptor(id: formatContext, version: 1, title: "Format as context")
        ]
}

public struct TextRecipe: Codable, Identifiable, Sendable, Equatable {
    public static let currentVersion = 1
    public static let maximumSteps = 8
    public static let maximumNameLength = 80
    public var id: UUID
    public var version: Int
    public var name: String
    public var steps: [TextActionStep]

    public init(
        id: UUID = UUID(), version: Int = currentVersion, name: String, steps: [TextActionStep]
    ) {
        self.id = id
        self.version = version
        self.name = name
        self.steps = steps
    }

    /// Structure can be inspected without deleting unknown actions or versions.
    public func validateStructure() throws {
        guard version == Self.currentVersion else { throw TextRecipeError.unsupportedVersion }
        let visibleName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !visibleName.isEmpty, visibleName.count <= Self.maximumNameLength,
            !steps.isEmpty, steps.count <= Self.maximumSteps,
            Set(steps.map(\.id)).count == steps.count
        else { throw TextRecipeError.invalidDefinition }
    }

    public func validate() throws {
        try validateStructure()
        for step in steps { try step.validate() }
    }
}

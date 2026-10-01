import GanchoKit

@MainActor public enum TextRecipeDelivery {
    public enum Outcome: Sendable, Equatable {
        case copied, clipboardChanged, selectionChanged, blocked
    }
    public static func copy(
        result: String, expected: CombinedTextPart, from store: any ClipReading,
        clipboardUnchanged: () -> Bool, isAllowed: () -> Bool, write: (String) -> Void
    ) async throws -> Outcome {
        try Task.checkCancellation()
        guard result.utf8.count <= TextRecipeExecutor.maximumUTF8Bytes else {
            throw TextRecipeError.tooLarge
        }
        let current = try await CombinedTextService().load(ids: [expected.id], from: store)
        try Task.checkCancellation()
        guard isAllowed() else { return .blocked }
        guard current == [expected], case .text = expected.content else { return .selectionChanged }
        guard clipboardUnchanged() else { return .clipboardChanged }
        write(result)
        return .copied
    }
}

import GanchoKit

/// Main-actor validation cannot interleave with this app's state changes.
/// Check the external clipboard immediately before writing; platform I/O stays injected.
@MainActor public enum CombinedTextCopy {
    public enum Outcome: Sendable, Equatable {
        case copied
        case changed([CombinedTextPart])
        case blocked
        case invalid
    }

    public static func perform(
        expected: [CombinedTextPart], separator: String, from store: any ClipReading,
        clipboardUnchanged: () -> Bool,
        isAllowed: () -> Bool, write: (String) -> Void
    ) async throws -> Outcome {
        try Task.checkCancellation()
        let service = CombinedTextService()
        let current = try await service.load(ids: expected.map(\.id), from: store)
        try Task.checkCancellation()
        guard isAllowed() else { return .blocked }
        guard current == expected else { return .changed(current) }
        guard let result = try service.compose(current, separator: separator) else {
            return .invalid
        }
        try Task.checkCancellation()
        guard clipboardUnchanged() else { return .changed(current) }
        write(result)
        return .copied
    }
}

import Foundation
import GanchoAI
import GanchoKit

public enum ManualImageTextError: Error { case unavailable }

/// Explicit OCR is independent of automatic Pro enrichment and its preference.
public struct ManualImageTextService: Sendable {
    public init() {}

    public func text(
        for id: UUID, store: any ImageTextReading,
        recognize: @Sendable (Data) async throws -> String? = {
            try await ImageTextExtractor().extractText(from: $0)
        }
    ) async throws -> String? {
        try Task.checkCancellation()
        let input = try await store.imageTextInput(id: id, now: .now)
        try Task.checkCancellation()
        switch input {
        case .cached(let text): return text
        case .image(let data):
            let result = try await recognize(data)
            try Task.checkCancellation()
            return result
        case nil: throw ManualImageTextError.unavailable
        }
    }
}

import Foundation
import GanchoAI
import GanchoKit

public enum ManualImageTextError: Error { case unavailable }

/// What one explicit OCR request produced: the lines in reading order, with
/// their regions when recognition produced them (text that was already stored
/// by automatic enrichment has none).
public struct ManualOCRResult: Sendable, Equatable {
    public let lines: [RecognizedTextLine]

    /// Blank lines never survive: they would count as text and copy as noise.
    public init(lines: [RecognizedTextLine]) {
        self.lines = lines.filter {
            !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Stored text, split into lines without regions.
    public init(text: String) {
        self.init(
            lines: text.split(separator: "\n", omittingEmptySubsequences: false)
                .map { RecognizedTextLine(text: String($0)) })
    }

    public var text: String { lines.map(\.text).joined(separator: "\n") }
    public var isEmpty: Bool { lines.isEmpty }
}

/// Explicit OCR is independent of automatic Pro enrichment and its preference.
public struct ManualImageTextService: Sendable {
    public init() {}

    public func result(
        for id: UUID, store: any ImageTextReading,
        recognize: @Sendable (Data) async throws -> [RecognizedTextLine] = {
            try await ImageTextExtractor().recognizeLines(in: $0)
        }
    ) async throws -> ManualOCRResult? {
        try Task.checkCancellation()
        let input = try await store.imageTextInput(id: id, now: .now)
        try Task.checkCancellation()
        switch input {
        case .cached(let text): return ManualOCRResult(text: text)
        case .image(let data):
            let lines = try await recognize(data)
            try Task.checkCancellation()
            return ManualOCRResult(lines: lines)
        case nil: throw ManualImageTextError.unavailable
        }
    }
}

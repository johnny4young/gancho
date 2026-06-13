import CoreGraphics
import Foundation
import ImageIO
import Vision

/// On-device OCR over image clips (Vision). The extracted text attaches to
/// the clip row's contentText, which makes screenshots SEARCHABLE through
/// the same FTS index — no separate pipeline. Zero network, like every
/// intelligence tier.
public struct ImageTextExtractor: Sendable {
    public init() {}

    /// nil when the image carries no recognizable text.
    public func extractText(from imageData: Data) async throws -> String? {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { return nil }

        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let observations = try await request.perform(on: image)

        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

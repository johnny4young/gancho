import CoreGraphics
import Foundation
import ImageIO
import Vision

/// On-device image OCR (Vision), with no persistence or network effects.
/// Automatic enrichment may index the result; explicit copy keeps it transient.
public struct ImageTextExtractor: Sendable {
    public init() {}

    /// nil when the image carries no recognizable text.
    @concurrent
    public func extractText(from imageData: Data) async throws -> String? {
        try Task.checkCancellation()
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else { throw ImageTextExtractionError.invalidImage }

        try Task.checkCancellation()
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let orientation =
            CGImagePropertyOrientation(
                rawValue: (properties?[kCGImagePropertyOrientation] as? UInt32) ?? 1) ?? .up
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.automaticallyDetectsLanguage = true
        let observations = try await request.perform(on: image, orientation: orientation)
        try Task.checkCancellation()

        let lines = observations.compactMap { $0.topCandidates(1).first?.string }
        let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }
}

public enum ImageTextExtractionError: Error { case invalidImage }

import CoreGraphics
import Foundation
import ImageIO
import Vision

/// One recognized line and where it sits in the source image.
public struct RecognizedTextLine: Sendable, Equatable {
    public let text: String
    /// Normalized to the oriented image (0…1 on both axes) with the origin at
    /// the TOP-LEFT, so a view can map it straight onto a rendered thumbnail.
    /// Vision reports a bottom-left origin; the extractor flips it once, here.
    /// nil when the line came from stored text and never had a region.
    public let box: CGRect?

    public init(text: String, box: CGRect? = nil) {
        self.text = text
        self.box = box
    }
}

/// On-device image OCR (Vision), with no persistence or network effects.
/// Automatic enrichment may index the result; explicit copy keeps it transient.
public struct ImageTextExtractor: Sendable {
    public init() {}

    /// nil when the image carries no recognizable text.
    @concurrent
    public func extractText(from imageData: Data) async throws -> String? {
        let text = try await recognizeLines(in: imageData).map(\.text).joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// Every recognized line in reading order — top to bottom, then left to
    /// right — each with the region it was read from. Empty when the image
    /// carries no recognizable text.
    @concurrent
    public func recognizeLines(in imageData: Data) async throws -> [RecognizedTextLine] {
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

        let lines = observations.compactMap { observation -> RecognizedTextLine? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            let rect = observation.boundingBox.cgRect
            let topLeft = CGRect(
                x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height)
            return RecognizedTextLine(text: text, box: topLeft)
        }
        return Self.readingOrder(lines)
    }

    /// Vision usually reports lines top-down already, but not always for
    /// columns or rotated scans. Sort by row, then by x within a row; two
    /// lines share a row when their vertical centres are closer than half the
    /// smaller line height.
    static func readingOrder(_ lines: [RecognizedTextLine]) -> [RecognizedTextLine] {
        // Lines without a region (stored text) never enter the geometric
        // comparison: they keep their order and follow the placed ones.
        let placed = lines.compactMap { line in line.box.map { (line: line, box: $0) } }
            .sorted { lhs, rhs in
                let tolerance = min(lhs.box.height, rhs.box.height) / 2
                if abs(lhs.box.midY - rhs.box.midY) <= tolerance {
                    return lhs.box.minX < rhs.box.minX
                }
                return lhs.box.midY < rhs.box.midY
            }
            .map(\.line)
        return placed + lines.filter { $0.box == nil }
    }
}

public enum ImageTextExtractionError: Error { case invalidImage }

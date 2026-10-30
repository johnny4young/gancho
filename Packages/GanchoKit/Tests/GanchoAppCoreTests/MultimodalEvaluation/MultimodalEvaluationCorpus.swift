import CoreGraphics
import Foundation

/// Frozen synthetic captures and queries for comparing image retrieval strategies.
/// Captures are rendered at test time; no real clipboard history is involved.
enum MultimodalEvaluationCorpus {
    /// Bump when a capture, query or expected answer changes, so receipts stay comparable.
    static let revision = 1

    enum Colour: String, CaseIterable { case red, blue, green, yellow, purple, orange }
    enum ShapeKind: String { case circle, square, triangle }

    /// `frame` is in a 0…1 unit square with a top-left origin.
    struct Shape: Equatable {
        let kind: ShapeKind
        let colour: Colour
        let frame: CGRect
    }

    enum Scene: Equatable {
        case dialog(title: String, message: String, code: String)
        /// Left-to-right boxes joined by arrows, first to last.
        case diagram(nodes: [String])
        case barChart(title: String, labels: [String], values: [Double])
        case statusScreen(title: String, lines: [String])
        /// Deliberately text-free, so OCR has nothing to read.
        case shapes([Shape])
        /// Stored as a text clip, never rendered.
        case text(String)

        var isImage: Bool {
            if case .text = self { return false }
            return true
        }
    }

    struct Capture {
        let key: String
        let id: UUID
        let scene: Scene
    }

    enum Category: String, CaseIterable {
        case identifier, ocrParaphrase, visualRelation, visualOnly, unanswered
    }

    struct Query {
        let name: String
        let language: String
        let category: Category
        let heldOut: Bool
        let text: String
        let expectedKeys: Set<String>
    }

    static let captures: [Capture] = scenes.enumerated().map { index, entry in
        Capture(key: entry.key, id: identifier(index: index), scene: entry.scene)
    }

    static let capturesByKey = Dictionary(uniqueKeysWithValues: captures.map { ($0.key, $0) })

    static func expectedIDs(_ query: Query) -> Set<UUID> {
        Set(query.expectedKeys.compactMap { capturesByKey[$0]?.id })
    }

    /// The 0xA7 prefix keeps these ids apart from every other synthetic corpus.
    static func identifier(index: Int) -> UUID {
        UUID(uuid: (0xA7, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, UInt8(index + 1)))
    }
}

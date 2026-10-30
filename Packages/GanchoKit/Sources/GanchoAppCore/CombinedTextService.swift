import Foundation
import GanchoAI
import GanchoKit

public struct CombinedTextPart: Identifiable, Sendable, Equatable {
    public enum Content: Sendable, Equatable {
        case text(String)
        /// An image's stored OCR text. Only a caller that asks for it receives
        /// it, and it is never delivered until the user approves it explicitly.
        case recognizedText(String)
        case unavailable, incompatible, protected, tooLarge
    }
    /// Bounded display-only excerpt. The complete text remains unchanged for
    /// validation and delivery.
    public var preview: String? {
        switch content {
        case .text(let text), .recognizedText(let text):
            BoundedPreview.make(text, maximumScalars: 80)
        case .unavailable, .incompatible, .protected, .tooLarge: nil
        }
    }

    public let id: UUID
    public let content: Content
    public init(id: UUID, content: Content) {
        self.id = id
        self.content = content
    }
}

/// Reads only explicitly selected text-backed clips. No writes or side effects.
public struct CombinedTextService: Sendable {
    public static let maximumClips = 100
    public static let maximumUTF8Bytes = 1_048_576

    public init() {}

    /// `recognizedText` opts images into their stored OCR text; without it an
    /// image stays incompatible, as every combined-copy surface expects.
    public func load(
        ids: [UUID], from store: any ClipReading,
        recognizedText: (any StoredImageTextReading)? = nil
    ) async throws -> [CombinedTextPart] {
        guard ids.count <= Self.maximumClips else { throw TextCompositionError.tooLarge }
        let visible = Dictionary(
            try await store.items(ids: ids).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first })
        var parts: [CombinedTextPart] = []
        for id in ids {
            try Task.checkCancellation()
            let content: CombinedTextPart.Content
            if let item = visible[id] {
                // The same policy every preview surface applies: detector-flagged
                // rows AND inherently masked kinds (a bare JWT or card number is
                // stored non-sensitive on purpose) never leave the store in clear.
                if ClipSafePresentation.requiresMasking(item)
                    || item.expiresAt.map({ $0 <= .now }) == true
                {
                    content = .protected
                } else if item.kind == .image, let recognizedText,
                    let text = try await recognizedText.storedImageText(id: id, now: .now)
                {
                    content = Self.recognizedContent(text)
                } else if item.kind == .image || item.kind == .fileReference {
                    content = .incompatible
                } else if case .text(let text) = try await store.content(for: id) {
                    content = text.utf8.count > Self.maximumUTF8Bytes ? .tooLarge : .text(text)
                } else {
                    content = .incompatible
                }
            } else {
                content = .unavailable
            }
            parts.append(CombinedTextPart(id: id, content: content))
        }
        try Task.checkCancellation()
        // Revalidate the entire batch after all content reads. Checking each
        // row immediately after reading it leaves earlier rows unprotected
        // while a later read suspends, and adds one metadata query per clip.
        let current = Dictionary(
            try await store.items(ids: ids).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first })
        try Task.checkCancellation()
        return parts.map { part in
            switch part.content {
            case .text, .recognizedText: break
            case .unavailable, .incompatible, .protected, .tooLarge: return part
            }
            guard let before = visible[part.id], let after = current[part.id],
                !ClipSafePresentation.requiresMasking(after), after.kind == before.kind,
                after.updatedAt == before.updatedAt, after.contentHash == before.contentHash,
                after.expiresAt.map({ $0 > .now }) ?? true
            else { return CombinedTextPart(id: part.id, content: .unavailable) }
            return part
        }
    }

    /// Enrichment drops secret-looking OCR text when it stores it; text stored
    /// before a newer rule, or by any other writer, is checked again here.
    static func recognizedContent(
        _ text: String, detector: SensitiveDataDetector = SensitiveDataDetector()
    ) -> CombinedTextPart.Content {
        if detector.detect(text) != nil { return .protected }
        return text.utf8.count > maximumUTF8Bytes ? .tooLarge : .recognizedText(text)
    }

    public func compose(_ parts: [CombinedTextPart], separator: String) throws -> String? {
        guard !parts.isEmpty, parts.count <= Self.maximumClips else { return nil }
        var texts: [String] = []
        for part in parts {
            guard case .text(let text) = part.content else { return nil }
            texts.append(text)
        }
        return try TextComposition.join(
            texts, separator: separator, maximumUTF8Bytes: Self.maximumUTF8Bytes)
    }
}

/// Display-only prefix bounded by Unicode scalars, since one grapheme can contain
/// arbitrarily many marks. Whole characters are kept while they fit, so emoji
/// sequences are never split; a single oversized grapheme is cut by scalars.
public enum BoundedPreview {
    public static func make(_ text: String, maximumScalars limit: Int) -> String {
        var used = 0
        var end = text.startIndex
        for character in text {
            used += character.unicodeScalars.count
            guard used <= limit else { break }
            end = text.index(after: end)
        }
        if end == text.startIndex, !text.isEmpty {
            return String(String.UnicodeScalarView(text.unicodeScalars.prefix(limit)))
        }
        return String(text[..<end])
    }
}

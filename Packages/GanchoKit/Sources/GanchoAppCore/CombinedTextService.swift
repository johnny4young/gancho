import Foundation
import GanchoKit

public struct CombinedTextPart: Identifiable, Sendable, Equatable {
    public enum Content: Sendable, Equatable {
        case text(String)
        case unavailable, incompatible, protected, tooLarge
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

    public func load(ids: [UUID], from store: any ClipReading) async throws -> [CombinedTextPart] {
        guard ids.count <= Self.maximumClips else { throw TextCompositionError.tooLarge }
        let visible = Dictionary(
            try await store.items(ids: ids).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first })
        var parts: [CombinedTextPart] = []
        for id in ids {
            try Task.checkCancellation()
            let content: CombinedTextPart.Content
            if let item = visible[id] {
                if item.isSensitive || item.kind == .secret
                    || item.expiresAt.map({ $0 <= .now }) == true
                {
                    content = .protected
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
            guard case .text = part.content else { return part }
            guard let before = visible[part.id], let after = current[part.id],
                !after.isSensitive, after.kind != .secret, after.kind == before.kind,
                after.updatedAt == before.updatedAt, after.contentHash == before.contentHash,
                after.expiresAt.map({ $0 > .now }) ?? true
            else { return CombinedTextPart(id: part.id, content: .unavailable) }
            return part
        }
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

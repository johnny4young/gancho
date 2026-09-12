import Foundation
import GRDB

/// The two read-only inputs for explicit image OCR. No enrichment writes or
/// sync side effects are granted to callers of this facet.
public enum ImageTextInput: Sendable, Equatable {
    case cached(String)
    case image(Data)
}

public protocol ImageTextReading: Sendable {
    func imageTextInput(id: UUID, now: Date) async throws -> ImageTextInput?
    func permitsImageText(id: UUID, now: Date) async throws -> Bool
}

extension GRDBClipboardStore: ImageTextReading {
    public func permitsImageText(id: UUID, now: Date) async throws -> Bool {
        try await writer.read { db in
            guard
                let row = try ClipRow.select(ClipRow.metadataColumns).filter(key: id.uuidString)
                    .fetchOne(db)
            else { return false }
            return Self.permitsImageText(row, now: now)
        }
    }

    public func imageTextInput(id: UUID, now: Date) async throws -> ImageTextInput? {
        let row = try await writer.read { db in
            try ClipRow.filter(key: id.uuidString).fetchOne(db)
        }
        guard let row, Self.permitsImageText(row, now: now) else { return nil }
        if let text = row.contentText, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return .cached(text)
        }
        guard case .binary(let data, _) = try await content(for: id) else { return nil }
        return .image(data)
    }

    private static func permitsImageText(_ row: ClipRow, now: Date) -> Bool {
        row.kind == ClipContentKind.image.rawValue && !row.isArchived && !row.isSensitive
            && (row.expiresAt.map { $0 > now } ?? true)
    }
}

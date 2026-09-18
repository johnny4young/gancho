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
    /// Exactly the columns the permission predicate reads. Deliberately NOT
    /// `ClipRow.metadataColumns`: that list carries `title` and `preview`, so
    /// every check would materialize the clip's own text — including for the
    /// sensitive rows this predicate exists to refuse — and one OCR request
    /// checks permission three times (before the read, after recognition, and
    /// again for each review action).
    private static let permissionColumns = [
        Column("kind"), Column("isArchived"), Column("isSensitive"), Column("expiresAt")
    ]

    public func permitsImageText(id: UUID, now: Date) async throws -> Bool {
        try await writer.read { db in
            guard
                let row = try ClipRow.filter(key: id.uuidString)
                    .select(Self.permissionColumns).asRequest(of: Row.self).fetchOne(db)
            else { return false }
            let expiresAt: Date? = row["expiresAt"]
            return Self.permitsImageText(
                kind: row["kind"], isArchived: row["isArchived"],
                isSensitive: row["isSensitive"], expiresAt: expiresAt, now: now)
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
        permitsImageText(
            kind: row.kind, isArchived: row.isArchived, isSensitive: row.isSensitive,
            expiresAt: row.expiresAt, now: now)
    }

    /// One predicate for both readers, so the narrow permission projection and
    /// the full-row read can never drift apart on what "permitted" means.
    private static func permitsImageText(
        kind: String, isArchived: Bool, isSensitive: Bool, expiresAt: Date?, now: Date
    ) -> Bool {
        kind == ClipContentKind.image.rawValue && !isArchived && !isSensitive
            && (expiresAt.map { $0 > now } ?? true)
    }
}

import Foundation
import GRDB

/// One paste of a stored clip into another app: ids and a time, no content.
public struct PasteEvent: Sendable, Equatable {
    public let clipID: UUID
    public let pastedAt: Date

    public init(clipID: UUID, pastedAt: Date) {
        self.clipID = clipID
        self.pastedAt = pastedAt
    }
}

/// The local paste log behind Up next. It never syncs, never exports, keeps a
/// rolling window, and leaves out secrets and masked kinds.
public protocol PasteEventLogging: Sendable {
    /// Logs pastes into one app. Unknown clips, secrets, masked kinds and an
    /// invalid bundle id are skipped.
    func recordPasteEvents(clipIDs: [UUID], targetBundleID: String, at date: Date) async throws

    /// The window's pastes into one app, newest first.
    func pasteEvents(targetBundleID: String, now: Date) async throws -> [PasteEvent]

    /// Deletes rows older than the window.
    func prunePasteEvents(now: Date) async throws

    /// Erases the whole log; turning Up next off calls it.
    func clearPasteEvents() async throws
}

public enum PasteEventLog {
    public static let window: TimeInterval = 30 * 24 * 60 * 60
    static let readLimit = 2_000

    static func registerMigration(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration(GanchoDatabaseMigrator.Identifier.pasteEvents.rawValue) { db in
            try db.create(table: "paste_event") { table in
                table.column("clipID", .text).notNull().indexed()
                    .references("clip", onDelete: .cascade)
                table.column("targetBundleID", .text).notNull()
                table.column("pastedAt", .datetime).notNull()
            }
            try db.create(
                index: "idx_paste_event_target_time", on: "paste_event",
                columns: ["targetBundleID", "pastedAt"])
            // A clip that turns secret leaves the log at once.
            try db.execute(
                sql: """
                    CREATE TRIGGER paste_event_drops_secrets
                    AFTER UPDATE OF isSensitive ON clip WHEN NEW.isSensitive = 1
                    BEGIN DELETE FROM paste_event WHERE clipID = NEW.id; END
                    """)
        }
    }

    /// `kind NOT IN (…)` over the masked kinds, for the clip join.
    static var maskedKindsSQL: String {
        ClipContentKind.allCases.filter(\.prefersMaskedPreview)
            .map { "'\($0.rawValue)'" }.joined(separator: ", ")
    }
}

extension GRDBClipboardStore: PasteEventLogging {
    public func recordPasteEvents(
        clipIDs: [UUID], targetBundleID: String, at date: Date = .now
    ) async throws {
        guard !clipIDs.isEmpty, BundleIdentifierShape.isValid(targetBundleID) else { return }
        let cutoff = date.addingTimeInterval(-PasteEventLog.window)
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM paste_event WHERE pastedAt < ?", arguments: [cutoff])
            for id in Set(clipIDs) {
                try db.execute(
                    sql: """
                        INSERT INTO paste_event (clipID, targetBundleID, pastedAt)
                        SELECT id, ?, ? FROM clip
                        WHERE id = ? AND isSensitive = 0
                            AND kind NOT IN (\(PasteEventLog.maskedKindsSQL))
                        """,
                    arguments: [targetBundleID, date, id.uuidString])
            }
        }
    }

    public func pasteEvents(targetBundleID: String, now: Date = .now) async throws -> [PasteEvent] {
        guard BundleIdentifierShape.isValid(targetBundleID) else { return [] }
        let cutoff = now.addingTimeInterval(-PasteEventLog.window)
        return try await writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT e.clipID, e.pastedAt FROM paste_event e
                    JOIN clip c ON c.id = e.clipID
                    WHERE e.targetBundleID = ? AND e.pastedAt >= ?
                        AND c.isSensitive = 0 AND c.kind NOT IN (\(PasteEventLog.maskedKindsSQL))
                    ORDER BY e.pastedAt DESC LIMIT ?
                    """,
                arguments: [targetBundleID, cutoff, PasteEventLog.readLimit]
            ).compactMap { row in
                let id: String = row["clipID"]
                return UUID(uuidString: id).map {
                    PasteEvent(clipID: $0, pastedAt: row["pastedAt"])
                }
            }
        }
    }

    public func prunePasteEvents(now: Date = .now) async throws {
        let cutoff = now.addingTimeInterval(-PasteEventLog.window)
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM paste_event WHERE pastedAt < ?", arguments: [cutoff])
        }
    }

    public func clearPasteEvents() async throws {
        try await writer.write { db in try db.execute(sql: "DELETE FROM paste_event") }
    }
}

/// CFBundleIdentifier's shape: ASCII alphanumerics, hyphen and period, no
/// empty labels. Rejecting other text keeps content out of id columns.
enum BundleIdentifierShape {
    static let maximumLength = 255

    static func isValid(_ value: String) -> Bool {
        !value.isEmpty
            && value.utf8.count <= maximumLength
            && value.first != "."
            && value.last != "."
            && !value.contains("..")
            && value.unicodeScalars.allSatisfy(isAllowed)
    }

    private static func isAllowed(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 45, 46, 48...57, 65...90, 97...122: true
        default: false
        }
    }
}

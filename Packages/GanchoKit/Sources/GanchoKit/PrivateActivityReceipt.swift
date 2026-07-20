import Foundation
import GRDB

/// One local application's aggregate contribution to the private activity
/// receipt. Bundle identifiers are retained only on this device and never ride
/// sync, telemetry, support bundles, or export.
public struct PrivateActivityAppStat: Sendable, Equatable {
    /// Nil is the honest bucket when the platform supplied no identifier or
    /// when the content-free identifier whitelist rejected the supplied value.
    public let bundleID: String?
    public let captures: Int
    public let reuses: Int

    public init(bundleID: String?, captures: Int, reuses: Int) {
        self.bundleID = bundleID
        self.captures = captures
        self.reuses = reuses
    }
}

/// Content-free, on-device proof of how Gancho has handled clipboard activity.
/// Every value is an integer aggregate over a rolling, bounded retention window.
public struct PrivateActivityReceipt: Sendable, Equatable {
    public let captures: Int
    public let reusedItems: Int
    public let skippedCaptures: Int
    public let protectedCaptures: Int
    public let sensitiveItemsExpired: Int
    public let retainedSince: Date
    public let appStats: [PrivateActivityAppStat]

    public init(
        captures: Int,
        reusedItems: Int,
        skippedCaptures: Int,
        protectedCaptures: Int,
        sensitiveItemsExpired: Int,
        retainedSince: Date,
        appStats: [PrivateActivityAppStat]
    ) {
        self.captures = captures
        self.reusedItems = reusedItems
        self.skippedCaptures = skippedCaptures
        self.protectedCaptures = protectedCaptures
        self.sensitiveItemsExpired = sensitiveItemsExpired
        self.retainedSince = retainedSince
        self.appStats = appStats
    }

    public static func empty(now: Date = .now) -> Self {
        Self(
            captures: 0,
            reusedItems: 0,
            skippedCaptures: 0,
            protectedCaptures: 0,
            sensitiveItemsExpired: 0,
            retainedSince: PrivateActivityReceiptSchema.retentionCutoff(from: now),
            appStats: [])
    }
}

private enum PrivateActivityReceiptSchema {
    static let retentionMonths = 13
    static let maximumEventIncrement = 1_000_000
    static let maximumCounter = 9_000_000_000_000_000
    static let maximumBundleIDLength = 255
    static let aggregateBucket = "__gancho.aggregate__"
    static let unknownAppBucket = "__gancho.unknown__"

    static func retentionCutoff(from date: Date) -> Date {
        guard let shifted = calendar.date(byAdding: .month, value: -retentionMonths, to: date)
        else { return .distantPast }
        return calendar.startOfDay(for: shifted)
    }

    static func dayKey(for date: Date) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(
            format: "%04d-%02d-%02d",
            components.year ?? 1,
            components.month ?? 1,
            components.day ?? 1)
    }

    static func appBucket(for rawBundleID: String?) -> String {
        guard let rawBundleID,
            !rawBundleID.isEmpty,
            rawBundleID.utf8.count <= maximumBundleIDLength,
            !rawBundleID.hasPrefix("__gancho."),
            rawBundleID.first != ".",
            rawBundleID.last != ".",
            !rawBundleID.contains(".."),
            rawBundleID.unicodeScalars.allSatisfy(isBundleIdentifierScalar)
        else {
            return unknownAppBucket
        }
        return rawBundleID
    }

    static func bounded(_ count: Int) -> Int {
        min(max(count, 0), maximumEventIncrement)
    }

    /// CFBundleIdentifier permits ASCII alphanumerics, hyphen, and period.
    /// Rejecting rather than cleaning invalid input prevents arbitrary text
    /// from becoming a content-shaped local history field.
    private static func isBundleIdentifierScalar(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 45, 46, 48...57, 65...90, 97...122: true
        default: false
        }
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

extension GRDBClipboardStore {
    /// v17 introduced the unused capture/paste table. v20 completes that
    /// content-free schema for the private receipt and adds a day-led index so
    /// rolling retention prunes do not scan the composite bundle-first key.
    static func registerPrivateActivityReceiptMigration(in migrator: inout DatabaseMigrator) {
        migrator.registerMigration(
            GanchoDatabaseMigrator.Identifier.privateActivityReceipt.rawValue
        ) { db in
            try db.alter(table: "clip_app_stats") { table in
                table.add(column: "skippedCaptures", .integer).notNull().defaults(to: 0)
                table.add(column: "protectedCaptures", .integer).notNull().defaults(to: 0)
                table.add(column: "sensitiveItemsExpired", .integer).notNull().defaults(to: 0)
            }
            try db.create(
                index: "idx_clip_app_stats_day",
                on: "clip_app_stats",
                columns: ["day"])
        }
    }

    /// Records successful capture events grouped by source app and UTC day.
    /// Duplicate clips still count as captures because Gancho handled the copy;
    /// this counter is event activity, not the current number of stored rows.
    public func recordPrivateCapture(
        sourceAppBundleID: String?, count: Int = 1, at date: Date = .now
    ) async throws {
        try await recordPrivateActivity(
            bundleID: PrivateActivityReceiptSchema.appBucket(for: sourceAppBundleID),
            date: date,
            captures: PrivateActivityReceiptSchema.bounded(count))
    }

    /// Records reused items grouped by destination app and UTC day. A batch
    /// contributes its item count, not one opaque action.
    public func recordPrivateReuse(
        targetAppBundleID: String?, itemCount: Int = 1, at date: Date = .now
    ) async throws {
        try await recordPrivateActivity(
            bundleID: PrivateActivityReceiptSchema.appBucket(for: targetAppBundleID),
            date: date,
            reuses: PrivateActivityReceiptSchema.bounded(itemCount))
    }

    /// Records a capture Gancho intentionally did not store. Protected captures
    /// are a subset of skipped captures, never an additional skipped event.
    public func recordPrivateSkippedCapture(
        isProtected: Bool, count: Int = 1, at date: Date = .now
    ) async throws {
        let bounded = PrivateActivityReceiptSchema.bounded(count)
        try await recordPrivateActivity(
            bundleID: PrivateActivityReceiptSchema.aggregateBucket,
            date: date,
            skipped: bounded,
            protected: isProtected ? bounded : 0)
    }

    /// Records sensitive rows removed by the retention engine. This is only a
    /// count; the deleted content and its metadata never enter this table.
    public func recordPrivateSensitiveExpiry(
        count: Int, at date: Date = .now
    ) async throws {
        try await recordPrivateActivity(
            bundleID: PrivateActivityReceiptSchema.aggregateBucket,
            date: date,
            sensitiveExpired: PrivateActivityReceiptSchema.bounded(count))
    }

    /// Returns the current rolling receipt and prunes rows older than 13 months
    /// in the same serialized writer transaction.
    public func privateActivityReceipt(now: Date = .now) async throws -> PrivateActivityReceipt {
        let cutoff = PrivateActivityReceiptSchema.retentionCutoff(from: now)
        let cutoffKey = PrivateActivityReceiptSchema.dayKey(for: cutoff)
        return try await writer.write { db in
            try Self.prunePrivateActivity(before: cutoffKey, in: db)

            let aggregateTotals = try Row.fetchOne(
                db,
                sql: """
                    SELECT COALESCE(SUM(skippedCaptures), 0) AS skipped,
                           COALESCE(SUM(protectedCaptures), 0) AS protected,
                           COALESCE(SUM(sensitiveItemsExpired), 0) AS sensitiveExpired
                    FROM clip_app_stats
                    WHERE bundleID = ?
                    """,
                arguments: [PrivateActivityReceiptSchema.aggregateBucket])
            let appRows = try Row.fetchAll(
                db,
                sql: """
                    SELECT bundleID,
                           COALESCE(SUM(captures), 0) AS captures,
                           COALESCE(SUM(pastes), 0) AS reuses
                    FROM clip_app_stats
                    WHERE captures > 0 OR pastes > 0
                    GROUP BY bundleID
                    ORDER BY SUM(captures) + SUM(pastes) DESC, bundleID ASC
                    """)

            var captures = 0
            var reuses = 0
            let appStats = appRows.map { row in
                let appCaptures = Self.nonnegativeCounter(row["captures"])
                let appReuses = Self.nonnegativeCounter(row["reuses"])
                captures = Self.saturatingCounterSum(captures, appCaptures)
                reuses = Self.saturatingCounterSum(reuses, appReuses)
                let storedBundleID: String = row["bundleID"]
                return PrivateActivityAppStat(
                    bundleID:
                        storedBundleID == PrivateActivityReceiptSchema.unknownAppBucket
                        ? nil : storedBundleID,
                    captures: appCaptures,
                    reuses: appReuses)
            }
            return PrivateActivityReceipt(
                captures: captures,
                reusedItems: reuses,
                skippedCaptures: Self.nonnegativeCounter(aggregateTotals?["skipped"]),
                protectedCaptures: Self.nonnegativeCounter(aggregateTotals?["protected"]),
                sensitiveItemsExpired: Self.nonnegativeCounter(
                    aggregateTotals?["sensitiveExpired"]),
                retainedSince: cutoff,
                appStats: appStats)
        }
    }

    /// Explicitly erases the receipt without touching clips, settings, sync,
    /// diagnostics, or the optional telemetry consent state.
    public func clearPrivateActivityReceipt() async throws {
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM clip_app_stats")
        }
    }

    private func recordPrivateActivity(
        bundleID: String,
        date: Date,
        captures: Int = 0,
        reuses: Int = 0,
        skipped: Int = 0,
        protected: Int = 0,
        sensitiveExpired: Int = 0
    ) async throws {
        guard captures + reuses + skipped + protected + sensitiveExpired > 0 else { return }
        let day = PrivateActivityReceiptSchema.dayKey(for: date)
        let cutoff = PrivateActivityReceiptSchema.dayKey(
            for: PrivateActivityReceiptSchema.retentionCutoff(from: date))
        let maximum = PrivateActivityReceiptSchema.maximumCounter
        try await writer.write { db in
            try Self.prunePrivateActivity(before: cutoff, in: db)
            try db.execute(
                sql: """
                    INSERT INTO clip_app_stats (
                        bundleID, day, captures, pastes, skippedCaptures,
                        protectedCaptures, sensitiveItemsExpired
                    ) VALUES (?, ?, ?, ?, ?, ?, ?)
                    ON CONFLICT(bundleID, day) DO UPDATE SET
                        captures = MIN(clip_app_stats.captures + excluded.captures, \(maximum)),
                        pastes = MIN(clip_app_stats.pastes + excluded.pastes, \(maximum)),
                        skippedCaptures = MIN(
                            clip_app_stats.skippedCaptures + excluded.skippedCaptures, \(maximum)),
                        protectedCaptures = MIN(
                            clip_app_stats.protectedCaptures + excluded.protectedCaptures, \(maximum)),
                        sensitiveItemsExpired = MIN(
                            clip_app_stats.sensitiveItemsExpired
                                + excluded.sensitiveItemsExpired, \(maximum))
                    """,
                arguments: [
                    bundleID, day, captures, reuses, skipped, protected, sensitiveExpired
                ])
        }
    }

    private static func prunePrivateActivity(before day: String, in db: Database) throws {
        try db.execute(sql: "DELETE FROM clip_app_stats WHERE day < ?", arguments: [day])
    }

    private static func nonnegativeCounter(_ value: Int64?) -> Int {
        Int(clamping: max(value ?? 0, 0))
    }

    private static func saturatingCounterSum(_ lhs: Int, _ rhs: Int) -> Int {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? .max : sum
    }
}

import Foundation

/// Semantic date buckets for grouping the history list (Raycast-style headers):
/// Today, Yesterday, This month, Last month, This year, Last year, Older.
///
/// A priority cascade, most specific first — a clip from earlier today is
/// `today`, never `thisMonth`. Buckets are contiguous when items are ordered by
/// `createdAt` descending, so grouping a sorted list is a single linear pass.
public enum DateBucket: String, CaseIterable, Sendable, Hashable {
    case today
    case yesterday
    case thisMonth
    case lastMonth
    case thisYear
    case lastYear
    case older

    /// Which bucket `date` falls in relative to `now`, in `calendar`'s timezone.
    public static func of(_ date: Date, now: Date, calendar: Calendar = .current) -> DateBucket {
        if calendar.isDate(date, inSameDayAs: now) { return .today }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
            calendar.isDate(date, inSameDayAs: yesterday)
        {
            return .yesterday
        }
        // `.month` granularity matches month AND year, so a same-month date in a
        // different year never slips through.
        if calendar.isDate(date, equalTo: now, toGranularity: .month) { return .thisMonth }
        if let lastMonth = calendar.date(byAdding: .month, value: -1, to: now),
            calendar.isDate(date, equalTo: lastMonth, toGranularity: .month)
        {
            return .lastMonth
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) { return .thisYear }
        if let lastYear = calendar.date(byAdding: .year, value: -1, to: now),
            calendar.isDate(date, equalTo: lastYear, toGranularity: .year)
        {
            return .lastYear
        }
        return .older
    }
}

import Foundation
import GanchoKit

/// One step of the Library's offset pagination, made safe against the two
/// things a plain `offset = loaded.count` gets wrong: a page that never
/// arrived (cancelled or failed read) and a store that moved underneath the
/// loaded rows (retention removed one, a capture landed above, a pin flipped).
///
/// The rule is anchor-checked paging. A follow-up page is fetched starting a
/// few rows BEFORE the loaded tail; when those overlap rows still match the
/// tail, nothing shifted and the remainder appends. When they don't, the
/// whole loaded range plus one page is re-read in a single query — one
/// consistent snapshot — and replaces the list, so rows are neither skipped
/// nor duplicated. Read failures leave the caller's state untouched; only a
/// page that arrived can say the scope ended.
public enum LibraryPager {
    public static let pageSize = 100
    /// Rows re-read before the tail to detect a shifted window. Small enough
    /// to be free, larger than any plausible burst between two page requests.
    public static let overlap = 8

    public enum Outcome: Sendable, Equatable {
        /// The complete list after this step, and whether the store ran out.
        case loaded([ClipItem], reachedEnd: Bool)
        /// The read threw (cancellation included). Keep the list and the EOF
        /// flag as they were; the next request tries again.
        case failed
    }

    /// - Parameters:
    ///   - loaded: what the view already shows, in store order.
    ///   - stopAt: for prefix scopes (pinned rows sit before every unpinned
    ///     one) — the first row this matches ends the scope; it and everything
    ///     after it are dropped and the outcome reports EOF.
    ///   - fetch: the store's paged read, `(offset, limit)`. Runs on the
    ///     caller's actor, so a view can hand over its model's store directly.
    public static func nextPage(
        loaded: [ClipItem],
        pageSize: Int = pageSize,
        stopAt: ((ClipItem) -> Bool)? = nil,
        isolation: isolated (any Actor)? = #isolation,
        fetch: (Int, Int) async throws -> [ClipItem]
    ) async -> Outcome {
        let overlap = min(overlap, loaded.count)
        let offset = loaded.count - overlap
        let fetched: [ClipItem]
        do {
            fetched = try await fetch(offset, overlap + pageSize)
        } catch {
            return .failed
        }
        let requested = overlap + pageSize
        let anchor = loaded.suffix(overlap).map(\.id)
        if fetched.prefix(overlap).map(\.id) == anchor {
            let (tail, stopped) = truncated(Array(fetched.dropFirst(overlap)), stopAt: stopAt)
            let known = Set(loaded.map(\.id))
            return .loaded(
                loaded + tail.filter { !known.contains($0.id) },
                reachedEnd: stopped || fetched.count < requested)
        }
        // The window moved. Re-read everything shown so far plus one page as
        // one snapshot rather than guessing which rows shifted where.
        let span = loaded.count + pageSize
        let snapshot: [ClipItem]
        do {
            snapshot = try await fetch(0, span)
        } catch {
            return .failed
        }
        let (rows, stopped) = truncated(snapshot, stopAt: stopAt)
        return .loaded(deduplicated(rows), reachedEnd: stopped || snapshot.count < span)
    }

    private static func truncated(
        _ rows: [ClipItem], stopAt: ((ClipItem) -> Bool)?
    ) -> (rows: [ClipItem], stopped: Bool) {
        guard let stopAt, let end = rows.firstIndex(where: stopAt) else { return (rows, false) }
        return (Array(rows[..<end]), true)
    }

    private static func deduplicated(_ rows: [ClipItem]) -> [ClipItem] {
        var seen = Set<UUID>()
        return rows.filter { seen.insert($0.id).inserted }
    }
}

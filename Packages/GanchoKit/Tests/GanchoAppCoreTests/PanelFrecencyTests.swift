import Foundation
import GanchoKit
import Testing

@testable import GanchoAppCore

/// The frecency re-rank blends the store's BM25 order (position proxy) with
/// per-clip habit (uses × recency decay). Search-only — the recent list never
/// goes through `reranked`.
@Suite("Panel frecency re-rank")
struct PanelFrecencyTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func clip(
        _ tag: String, uses: Int = 0, lastUsedDaysAgo: Double? = nil
    ) -> ClipItem {
        ClipItem(
            lastUsedAt: lastUsedDaysAgo.map { now.addingTimeInterval(-$0 * 86_400) },
            preview: tag, contentHash: tag, uses: uses)
    }

    @Test("Unused clips keep the store's BM25 order")
    func unusedKeepsStoreOrder() {
        let hits = [clip("first"), clip("second"), clip("third")]
        #expect(
            PanelSearchModel.reranked(hits, now: now).map(\.preview)
                == ["first", "second", "third"])
    }

    @Test("A clip pasted 10 times yesterday outranks a slightly better match from 90 days ago")
    func habitBeatsSlightlyBetterStaleMatch() {
        // The acceptance scenario: positions 0 and 1 are the (stale) better text
        // matches; position 2 is the clip the user actually pastes daily.
        let hits = [
            clip("stale-best", uses: 0, lastUsedDaysAgo: 90),
            clip("stale-second", uses: 0, lastUsedDaysAgo: 90),
            clip("habitual", uses: 10, lastUsedDaysAgo: 1)
        ]
        #expect(PanelSearchModel.reranked(hits, now: now).first?.preview == "habitual")
    }

    @Test("Habit decays: the same use count from months ago no longer outranks")
    func frecencyDecays() {
        let hits = [
            clip("fresh-match", uses: 0),
            clip("forgotten-habit", uses: 10, lastUsedDaysAgo: 300)
        ]
        #expect(
            PanelSearchModel.reranked(hits, now: now).map(\.preview)
                == ["fresh-match", "forgotten-habit"],
            "a decayed habit must not beat a better current match")
    }

    @Test("A never-used clip with a nil lastUsedAt gets no boost")
    func nilLastUsedGetsNoBoost() {
        let undated = clip("counted-but-never-dated", uses: 5, lastUsedDaysAgo: nil)
        #expect(PanelSearchModel.frecencyScore(for: undated, now: now) == 0)

        let hits = [
            clip("top-match", uses: 0),
            undated
        ]
        #expect(
            PanelSearchModel.reranked(hits, now: now).map(\.preview)
                == ["top-match", "counted-but-never-dated"])
    }

    @Test("A future lastUsedAt (clock skew) is clamped, not amplified")
    func futureLastUsedClamps() {
        let hits = [
            clip("normal", uses: 3, lastUsedDaysAgo: 1),
            clip("skewed", uses: 3, lastUsedDaysAgo: -2)  // 2 days in the future
        ]
        // Both decay from ~0-1 days; the skewed one must not overflow past it
        // by orders of magnitude — order stays by position + comparable boost.
        let ranked = PanelSearchModel.reranked(hits, now: now).map(\.preview)
        #expect(ranked.first == "normal")
    }
}

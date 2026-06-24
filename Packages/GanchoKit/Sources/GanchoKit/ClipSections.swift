import Foundation

/// A history section: the pinned clips (always first), or one semantic date
/// bucket for the rest. Shared by every list surface — the iOS app and keyboard
/// today, the macOS panel can converge on it — so the grouping rule lives in
/// one place.
public enum ClipSection: Hashable, Sendable {
    case pinned
    case date(DateBucket)
}

/// A contiguous run of clips in one section, ready to render.
public struct ClipSectionGroup: Identifiable, Sendable {
    public let section: ClipSection
    public let clips: [ClipItem]

    public init(section: ClipSection, clips: [ClipItem]) {
        self.section = section
        self.clips = clips
    }

    /// Stable and unique per run — the first clip's id. Two sections never share
    /// a first clip, so a SwiftUI `ForEach` over groups never collides on ids
    /// even if a bucket somehow recurs out of order.
    public var id: UUID { clips.first?.id ?? UUID() }
}

public enum ClipSections {
    /// Group clips into contiguous sections — Pinned first, then date buckets.
    ///
    /// Assumes `clips` is already ordered pinned-first then by capture time
    /// descending (i.e. `GRDBClipboardStore.recentForBrowse`), so one linear
    /// pass yields contiguous sections whose order matches the visual order.
    public static func grouped(
        _ clips: [ClipItem], now: Date, calendar: Calendar = .current
    ) -> [ClipSectionGroup] {
        var groups: [ClipSectionGroup] = []
        var section: ClipSection?
        var run: [ClipItem] = []
        for clip in clips {
            let clipSection: ClipSection =
                clip.isPinned
                ? .pinned
                : .date(DateBucket.of(clip.createdAt, now: now, calendar: calendar))
            if clipSection != section {
                if let section { groups.append(ClipSectionGroup(section: section, clips: run)) }
                section = clipSection
                run = []
            }
            run.append(clip)
        }
        if let section { groups.append(ClipSectionGroup(section: section, clips: run)) }
        return groups
    }
}

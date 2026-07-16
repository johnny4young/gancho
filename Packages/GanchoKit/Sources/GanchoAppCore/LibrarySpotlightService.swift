import ClipboardCore
import Foundation
import GanchoKit

/// One donated Spotlight row: content-SAFE fields only. There is no field for
/// full clip text on purpose — the type is the boundary.
public struct SpotlightEntry: Sendable, Equatable {
    public let id: UUID
    /// The clip's title, or its first preview line when untitled.
    public let title: String
    /// The stored preview — safe by construction: unsafe items never map to
    /// an entry at all (see `entry(for:)`).
    public let summary: String
    /// The kind's raw token, for the result row's subtitle.
    public let kindLabel: String
}

/// The system-index writer the service drives. The CoreSpotlight adapter
/// lives in the app shells; tests use a fake, so the reconcile policy (what
/// is donated, when the domain is wiped) is fully unit-testable.
public protocol SpotlightIndexing: Sendable {
    /// Replace the entire Gancho domain with `entries` (wipe + index).
    func replaceAll(with entries: [SpotlightEntry]) async throws
    /// Remove every Gancho donation from the system index.
    func removeAll() async throws
}

/// Donates the curated Library — snippets and pinned clips ONLY — to
/// Spotlight, and nothing else, ever. Raw history, sensitive/expiring clips,
/// and masked credential kinds are excluded at the mapping layer, so a bug in
/// a caller cannot widen the surface. The one write shape is RECONCILE:
/// recompute the full curated set and replace the domain — after any curation
/// change (promote, demote, pin, unpin, delete) a reconcile IS the immediate
/// removal the demoted/deleted item needs, with no per-mutation bookkeeping.
/// The curated set is small by construction, so a full replace stays cheap.
public struct LibrarySpotlightService: Sendable {
    /// Pinned clips sit at the head of `recentForBrowse`; they are collected
    /// page by page so one over-pinned library cannot trigger an unbounded
    /// read. The cap is defensive — tiers bound pins far below it.
    static let pageSize = 50
    static let maxPinned = 500

    private let index: any SpotlightIndexing

    public init(index: any SpotlightIndexing) {
        self.index = index
    }

    /// The safety boundary, applied item by item: only a non-sensitive,
    /// non-expiring clip whose kind shows unmasked previews may become an
    /// entry. Archived clips never reach here (every read excludes them).
    public static func entry(for item: ClipItem) -> SpotlightEntry? {
        guard !item.isSensitive, item.expiresAt == nil, !item.kind.prefersMaskedPreview
        else { return nil }
        let firstLine = item.preview.split(separator: "\n").first.map(String.init) ?? ""
        let title = item.title.isEmpty ? firstLine : item.title
        guard !title.isEmpty else { return nil }
        return SpotlightEntry(
            id: item.id, title: title, summary: item.preview, kindLabel: item.kind.rawValue)
    }

    /// Recomputes the curated set (snippets + pinned, de-duplicated, safety-
    /// filtered) and replaces the Spotlight domain with it. `enabled: false`
    /// wipes the domain instead — the Settings toggle takes effect immediately.
    public func reconcile(
        store: any ClipReading & SnippetStoring, enabled: Bool
    ) async {
        guard enabled else {
            try? await index.removeAll()
            return
        }
        var items = (try? await store.snippets()) ?? []
        items += await pinnedItems(store: store)
        var seen = Set<UUID>()
        let entries = items.compactMap { item -> SpotlightEntry? in
            guard seen.insert(item.id).inserted else { return nil }
            return Self.entry(for: item)
        }
        try? await index.replaceAll(with: entries)
    }

    /// The pinned prefix of the browse order, page by page: pins float first,
    /// so collection stops at the first unpinned row.
    private func pinnedItems(store: any ClipReading) async -> [ClipItem] {
        var pinned: [ClipItem] = []
        var offset = 0
        while pinned.count < Self.maxPinned {
            guard
                let page = try? await store.recentForBrowse(
                    offset: offset, limit: Self.pageSize),
                !page.isEmpty
            else { break }
            let prefix = page.prefix(while: \.isPinned)
            pinned.append(contentsOf: prefix)
            if prefix.count < page.count { break }
            offset += page.count
        }
        return pinned
    }
}

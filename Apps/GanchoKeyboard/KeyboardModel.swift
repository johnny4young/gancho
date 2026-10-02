import GanchoKit
import ImageIO
import SwiftUI
import UIKit
import WidgetKit

/// Backs the keyboard UI. Reads the App Group store (only when Full Access is
/// granted), exposes the pin-first / search list as masked-safe entries, and
/// acts on a tap: text clips insert into the field, image clips copy the real
/// image to the pasteboard (a keyboard can't insert images directly). Reverse
/// capture goes through the shared `SharedCapture` pipeline.
@MainActor
final class KeyboardModel: ObservableObject {
    @Published var entries: [WidgetClipEntry] = []
    /// The grouped history (Pinned + date buckets), mirroring the app. Populated
    /// only on the plain recent view; a board filter or a search returns the flat
    /// `entries` instead.
    @Published var sections: [KeyboardClipSection] = []
    @Published var searchText = ""
    /// Open expanded by default: the searchable card list (with the board strip)
    /// is the useful view; the user can collapse to the one-row strip.
    @Published var expanded = true
    // A resource (not a bare key) so flashNote can also speak it to VoiceOver.
    @Published var note: LocalizedStringResource?
    @Published private(set) var saving = false
    /// Board filter (a higher axis than search). nil = all clips; otherwise the
    /// selected board, including the always-present Favorites. Synced boards
    /// made on other devices appear here too.
    @Published var boards: [Pinboard] = []
    @Published var selectedBoardID: UUID?
    /// Tiny downsampled image thumbnails, keyed by clip id. A keyboard runs under
    /// a hard memory budget, so this is capped (FIFO) and the decode never loads
    /// a full image — it decodes the store's small thumbnail bytes through
    /// ImageIO instead of opening the original screenshot.
    @Published private var thumbnails: [UUID: Image] = [:]
    private var thumbnailOrder: [UUID] = []
    private var thumbnailsInFlight: Set<UUID> = []
    private let maxThumbnails = 24

    let hasFullAccess: Bool
    let onDelete: () -> Void
    let onNextKeyboard: () -> Void
    var onModeChange: ((Bool) -> Void)?

    private let onInsert: (String) -> Void
    /// The store surface the keyboard needs: read + search the history, list a
    /// board's members, and sync-delete an entry. Held as facets so the keyboard
    /// depends on capabilities, not the concrete store.
    private let store: (any ClipReading & ClipSearching & BoardStoring & ClipMutating)?
    private var noteTask: Task<Void, Never>?
    /// The one in-flight list reload; each keystroke or board switch replaces it.
    private var reloadTask: Task<Void, Never>?

    init(
        hasFullAccess: Bool,
        onInsert: @escaping (String) -> Void,
        onDelete: @escaping () -> Void,
        onNextKeyboard: @escaping () -> Void
    ) {
        self.hasFullAccess = hasFullAccess
        self.onInsert = onInsert
        self.onDelete = onDelete
        self.onNextKeyboard = onNextKeyboard
        // No Full Access → no shared-container access → no store, no clips.
        store = hasFullAccess ? try? IntentStore.open() : nil
    }

    /// True on the plain recent view (no board, no query) — the only one that
    /// groups by Pinned + date, exactly like the app's history.
    var isGrouped: Bool {
        selectedBoardID == nil && searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// Pin-first history (sensitive excluded by `KeyboardClips`), narrowed to the
    /// selected board when one is active. Refreshes the board list each load so
    /// boards synced from other devices show up. The plain recent view groups
    /// into Pinned + date sections; a board view stays flat.
    func load() async {
        guard let store else { return }
        boards = (try? await store.pinboards()) ?? []
        let board = selectedBoardID
        if let board {
            // Strictly one small page — the keyboard extension runs under a
            // tight memory ceiling, and the store orders pinned-first so the
            // page keeps the pins on top.
            let page =
                (try? await store.search(KeyboardClips.query(boardID: board), limit: 60))
                ?? []
            guard isCurrent(text: "", board: board) else { return }
            entries = KeyboardClips.ordered(
                pinned: page.filter(\.isPinned), recent: page.filter { !$0.isPinned })
            sections = []
        } else {
            // Empty-text filtered search preserves pinned-first capture-time
            // ordering while excluding protected rows before LIMIT. Activity
            // ordering would split the date buckets after reusing an old clip.
            let recent = ((try? await store.search(KeyboardClips.query(), limit: 60)) ?? [])
                .filter { ClipSafeDelivery.isEligible($0) }
            guard isCurrent(text: "", board: nil) else { return }
            sections = ClipSections.grouped(recent, now: .now).compactMap { group in
                let entries = WidgetClips.entries(from: group.clips, limit: group.clips.count)
                return entries.isEmpty
                    ? nil : KeyboardClipSection(section: group.section, entries: entries)
            }
            entries = sections.flatMap(\.entries)
        }
    }

    func runSearch() async {
        guard let store else { return }
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            await load()
            return
        }
        let board = selectedBoardID
        let hits =
            (try? await store.search(
                KeyboardClips.query(text: trimmed, boardID: board), limit: 30)) ?? []
        // A slower, older query must not overwrite what the user typed since.
        guard isCurrent(text: trimmed, board: board) else { return }
        entries = WidgetClips.entries(
            from: hits.filter { ClipSafeDelivery.isEligible($0) }, limit: 30)
        sections = []
    }

    /// True while the result of a read for `text` and `board` still matches
    /// what the keyboard shows; a cancelled or superseded read drops its rows.
    private func isCurrent(text: String, board: UUID?) -> Bool {
        !Task.isCancelled && selectedBoardID == board
            && searchText.trimmingCharacters(in: .whitespaces) == text
    }

    /// Restart the reload for the current query, cancelling the previous one.
    func searchTextChanged() {
        scheduleReload()
    }

    private func scheduleReload() {
        reloadTask?.cancel()
        reloadTask = Task { await reloadCurrent() }
    }

    /// Switch the active board filter and reload through the current path
    /// (search results stay scoped if a query is present).
    func selectBoard(_ id: UUID?) {
        selectedBoardID = id
        scheduleReload()
    }

    /// Acts on a tapped clip: text/file refs insert into the field; images go
    /// to the pasteboard as REAL image data so the host app can paste them
    /// (the keyboard text proxy can't carry an image itself).
    func insert(_ entry: WidgetClipEntry) {
        guard let store else { return }
        Task {
            guard
                let payload = await ClipSafeDelivery.load(
                    id: entry.id, metadata: { try await store.item(id: $0) },
                    content: { try await store.content(for: $0) })
            else {
                flashNote("This clip is no longer available")
                return
            }
            switch payload.content {
            case .text(let text):
                onInsert(text)
            case .fileReferences(let paths):
                onInsert(paths.joined(separator: "\n"))
            case .binary(let data, let type):
                // A keyboard can only type text into another app — iOS has no
                // API to insert an image — so hand it off via the pasteboard and
                // tell the user how to drop it in (long-press the field → Paste).
                UIPasteboard.general.setData(data, forPasteboardType: type)
                flashNote("Image copied — long-press the field to paste")
            }
        }
    }

    /// Cached thumbnail for the row, or nil to fall back to the kind tile.
    func thumbnail(for id: UUID) -> Image? { thumbnails[id] }

    /// Loads one image clip's thumbnail, lazily and once. A no-op for non-images,
    /// sensitive clips, already-cached or in-flight ids. Reads the store's
    /// cached thumbnail bytes (never the full blob), downsamples off the main
    /// actor, and evicts the oldest once the cap is reached so memory stays
    /// bounded.
    func ensureThumbnail(_ entry: WidgetClipEntry) async {
        guard entry.kind == .image, !entry.isSensitive, let store,
            thumbnails[entry.id] == nil, !thumbnailsInFlight.contains(entry.id)
        else { return }
        thumbnailsInFlight.insert(entry.id)
        defer { thumbnailsInFlight.remove(entry.id) }
        guard let before = try? await store.item(id: entry.id),
            before.kind == .image, ClipSafeDelivery.isEligible(before),
            let data = try? await store.thumbnailData(for: entry.id)
        else { return }
        let decoded = await Task.detached { Self.downsample(data, maxPixel: 120) }.value
        guard let decoded, !Task.isCancelled,
            let current = try? await store.item(id: entry.id),
            ClipSafeDelivery.isSameRevision(current, before),
            ClipSafeDelivery.isEligible(current)
        else { return }
        thumbnails[entry.id] = Image(uiImage: decoded)
        thumbnailOrder.append(entry.id)
        if thumbnailOrder.count > maxThumbnails {
            let evicted = thumbnailOrder.removeFirst()
            if evicted != entry.id { thumbnails[evicted] = nil }
        }
    }

    /// Downsampled decode from already-small thumbnail bytes. ImageIO reads only
    /// enough to build a `maxPixel` thumbnail, so no original screenshot lands
    /// in the keyboard's memory whole.
    nonisolated private static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        guard
            let source = CGImageSourceCreateWithData(
                data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let options =
            [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: maxPixel
            ] as CFDictionary
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }

    /// Swipe → Copy: put the clip on the pasteboard (vs tap, which inserts it
    /// into the field) so it can be pasted in another app. Mirrors `insert`'s
    /// per-kind handling; images go on as real image data.
    func copy(_ entry: WidgetClipEntry) {
        guard let store else { return }
        Task {
            guard
                let payload = await ClipSafeDelivery.load(
                    id: entry.id, metadata: { try await store.item(id: $0) },
                    content: { try await store.content(for: $0) })
            else {
                flashNote("This clip is no longer available")
                return
            }
            switch payload.content {
            case .text(let text):
                UIPasteboard.general.string = text
            case .fileReferences(let paths):
                UIPasteboard.general.string = paths.joined(separator: "\n")
            case .binary(let data, let type):
                UIPasteboard.general.setData(data, forPasteboardType: type)
            }
            flashNote("Copied")
        }
    }

    /// Swipe → Delete: remove the clip and reload through the current path
    /// (search stays scoped if a query is present).
    ///
    /// Always `deleteForSync` (a tombstone + orphan-blob cleanup), never the
    /// plain delete: the extension can't see whether sync is on, and if it is, a
    /// plain delete would let the clip resurrect on the next pull. The tombstone
    /// is harmless when sync is off (it's pruned once acknowledged, otherwise
    /// just an inert row).
    func delete(_ entry: WidgetClipEntry) {
        guard let store else { return }
        Task {
            try? await store.deleteForSync(id: entry.id, now: .now)
            WidgetCenter.shared.reloadAllTimelines()
            scheduleReload()
        }
    }

    /// Reload via whichever path is active — the plain/board list or the search.
    private func reloadCurrent() async {
        if searchText.trimmingCharacters(in: .whitespaces).isEmpty {
            await load()
        } else {
            await runSearch()
        }
    }

    func toggleExpand() {
        expanded.toggle()
        onModeChange?(expanded)
        // No reload here: `entries` is already loaded; reloading caused a flash.
    }

    func saveClipboard() {
        guard !saving else { return }
        saving = true
        Task {
            let outcome = await SharedCapture.saveCurrentClipboard()
            saving = false
            flashNote(SharedCapture.message(for: outcome))
            if case .saved = outcome { WidgetCenter.shared.reloadAllTimelines() }
            scheduleReload()
        }
    }

    /// Shows a transient note and auto-clears it (cancelling any prior timer so
    /// rapid taps don't leave a stale message).
    private func flashNote(_ key: LocalizedStringResource) {
        note = key
        UIAccessibility.post(notification: .announcement, argument: String(localized: key))
        noteTask?.cancel()
        noteTask = Task {
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { note = nil }
        }
    }
}

/// One rendered history section in the keyboard: a `ClipSection` header (Pinned
/// or a date bucket) over its entries. Id is the first entry's id — stable and
/// unique per run, so a `ForEach` never collides even if a bucket recurs.
struct KeyboardClipSection: Identifiable, Equatable {
    let section: ClipSection
    let entries: [WidgetClipEntry]
    var id: UUID { entries.first?.id ?? UUID() }
}

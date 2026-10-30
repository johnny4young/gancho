import AppIntents
import GanchoKit
import SwiftUI
import WidgetKit

/// Home/lock-screen widget: the last few clips, each a deep link into the app,
/// plus an interactive "save the clipboard" button. Sensitive clips are
/// masked by `WidgetClips.entries` before they ever reach the timeline.
struct RecentClipsWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "RecentClips", provider: RecentClipsProvider()) { entry in
            RecentClipsView(entry: entry)
        }
        .configurationDisplayName("Recent Clips")
        .description("Your latest clips, with a one-tap save.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct RecentClipsEntry: TimelineEntry {
    let date: Date
    let clips: [WidgetClipEntry]
    /// The large widget's board chips and the board it shows (nil = all).
    var chips: [Pinboard] = []
    var boardID: UUID?
    var syncedAt: Date?
}

struct RecentClipsProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecentClipsEntry {
        RecentClipsEntry(date: .now, clips: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (RecentClipsEntry) -> Void) {
        let large = context.family == .systemLarge
        Task { completion(await Self.load(large: large)) }
    }

    func getTimeline(
        in context: Context, completion: @escaping (Timeline<RecentClipsEntry>) -> Void
    ) {
        let large = context.family == .systemLarge
        Task {
            let entry = await Self.load(large: large)
            // Periodic refresh; the app also reloads timelines right after a
            // capture, so the widget rarely waits this long.
            completion(
                Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(900))))
        }
    }

    /// Reads the recent clips from the App Group store and masks sensitive
    /// ones: three for small and medium, six (scoped to a board) for large.
    private static func load(large: Bool) async -> RecentClipsEntry {
        guard let store = try? IntentStore.open() else {
            return RecentClipsEntry(date: .now, clips: [])
        }
        guard large else {
            let items = (try? await store.items(offset: 0, limit: 3)) ?? []
            return RecentClipsEntry(date: .now, clips: WidgetClips.entries(from: items, limit: 3))
        }
        let boards = (try? await store.pinboards()) ?? []
        let chips = WidgetClips.boardChips(boards)
        // A board that is no longer a chip shows everything.
        let boardID = WidgetState.boardID.flatMap { id in chips.contains { $0.id == id } ? id : nil
        }
        let items =
            if let boardID {
                (try? await store.items(inBoard: boardID, offset: 0, limit: 6)) ?? []
            } else {
                (try? await store.items(offset: 0, limit: 6)) ?? []
            }
        return RecentClipsEntry(
            date: .now, clips: WidgetClips.entries(from: items, limit: 6), chips: chips,
            boardID: boardID, syncedAt: WidgetState.syncedAt)
    }
}

struct RecentClipsView: View {
    let entry: RecentClipsEntry

    @Environment(\.widgetFamily) private var family

    /// Small fits two rows comfortably; medium fits three.
    private var maxRows: Int { family == .systemSmall ? 2 : 3 }

    var body: some View {
        if family == .systemLarge {
            RecentClipsLargeView(entry: entry)
                .padding(14)
                .containerBackground(for: .widget) { background }
        } else {
            compact
        }
    }

    private var background: some View {
        LinearGradient(
            colors: [Color(.systemBackground), Color.accentColor.opacity(0.12)],
            startPoint: .top, endPoint: .bottom)
    }

    private var compact: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if entry.clips.isEmpty {
                emptyState
            } else {
                VStack(spacing: 5) {
                    ForEach(entry.clips.prefix(maxRows)) { clip in
                        clipRow(clip)
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .containerBackground(for: .widget) { background }
    }

    private var header: some View {
        HStack(spacing: 5) {
            Image("GanchoMarkTemplate")
                .resizable()
                .frame(width: 12, height: 12)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Recent clips")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            Spacer()
            Button(intent: SaveClipboardIntent()) {
                Image(systemName: "square.and.arrow.down")
                    .font(.caption.bold())
                    .foregroundStyle(.tint)
                    .padding(6)
                    .background(.tint.opacity(0.16), in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Save Clipboard")
        }
    }

    private func clipRow(_ clip: WidgetClipEntry) -> some View {
        Link(destination: clip.deepLinkURL ?? fallbackURL) {
            HStack(spacing: 8) {
                Image(systemName: clip.kind.symbolName)
                    .font(.caption2)
                    .foregroundStyle(.tint)
                    .frame(width: 16)
                Text(clip.displayText)
                    .font(.caption2)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(.fill.quaternary, in: .rect(cornerRadius: 8))
        }
    }

    private var emptyState: some View {
        VStack(spacing: 4) {
            Spacer()
            Image(systemName: "doc.on.clipboard")
                .font(.title3)
                .foregroundStyle(.tertiary)
            Text("Nothing yet")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text("Copy or share to Gancho")
                .font(.caption2)
                .foregroundStyle(.quaternary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var fallbackURL: URL { URL(string: "gancho://")! }
}

#if DEBUG
    private enum PreviewClips {
        static let favorites = Pinboard(name: "Favorites", isSystem: true)
        static let work = Pinboard(name: "Work", sortIndex: 0, colorHex: "#2E70D1")
        static let brand = Pinboard(name: "Brand", sortIndex: 1, colorHex: "#F08C08")

        static var entry: RecentClipsEntry {
            let now = Date.now
            func clip(
                _ kind: ClipContentKind, _ text: String, app: String, minutes: Double,
                masked: String? = nil, expires: Double? = nil
            ) -> WidgetClipEntry {
                WidgetClipEntry(
                    id: UUID(), title: "", displayText: masked == nil ? text : "•••", kind: kind,
                    isSensitive: masked != nil, sourceAppBundleID: app,
                    createdAt: now.addingTimeInterval(-minutes * 60), maskedTail: masked,
                    expiresAt: expires.map { now.addingTimeInterval($0) })
            }
            return RecentClipsEntry(
                date: now,
                clips: [
                    clip(.url, "example.com", app: "com.apple.mobilesafari", minutes: 7),
                    clip(.code, "let greeting = \"Hello\"", app: "com.apple.dt.Xcode", minutes: 0),
                    clip(.color, "Ocean · #008080", app: "com.figma.Desktop", minutes: 0),
                    clip(.image, "Synthetic landscape", app: "com.apple.Photos", minutes: 0),
                    clip(.text, "Meeting notes", app: "com.example.Portavoz", minutes: 2),
                    clip(
                        .secret, "", app: "com.apple.Terminal", minutes: 1, masked: "●●●● 4Q2v",
                        expires: 581)
                ],
                chips: [favorites, work, brand], boardID: nil,
                syncedAt: now.addingTimeInterval(-120))
        }
    }

    #Preview("Large", as: .systemLarge) {
        RecentClipsWidget()
    } timeline: {
        PreviewClips.entry
    }
#endif

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
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct RecentClipsEntry: TimelineEntry {
    let date: Date
    let clips: [WidgetClipEntry]
}

struct RecentClipsProvider: TimelineProvider {
    func placeholder(in context: Context) -> RecentClipsEntry {
        RecentClipsEntry(date: .now, clips: [])
    }

    func getSnapshot(in context: Context, completion: @escaping (RecentClipsEntry) -> Void) {
        Task { completion(await Self.load()) }
    }

    func getTimeline(
        in context: Context, completion: @escaping (Timeline<RecentClipsEntry>) -> Void
    ) {
        Task {
            let entry = await Self.load()
            // Periodic refresh; the app also reloads timelines right after a
            // capture, so the widget rarely waits this long.
            completion(
                Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(900))))
        }
    }

    /// Reads the last 3 clips from the App Group store and masks sensitive ones.
    private static func load() async -> RecentClipsEntry {
        guard let store = try? IntentStore.open(),
            let items = try? await store.items(offset: 0, limit: 3)
        else {
            return RecentClipsEntry(date: .now, clips: [])
        }
        return RecentClipsEntry(date: .now, clips: WidgetClips.entries(from: items, limit: 3))
    }
}

struct RecentClipsView: View {
    let entry: RecentClipsEntry

    @Environment(\.widgetFamily) private var family

    /// Small fits two rows comfortably; medium fits three.
    private var maxRows: Int { family == .systemSmall ? 2 : 3 }

    var body: some View {
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
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [Color(.systemBackground), Color.accentColor.opacity(0.12)],
                startPoint: .top, endPoint: .bottom)
        }
    }

    private var header: some View {
        HStack(spacing: 5) {
            Image(systemName: "paperclip")
                .font(.caption.bold())
                .foregroundStyle(.tint)
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
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var fallbackURL: URL { URL(string: "gancho://")! }
}

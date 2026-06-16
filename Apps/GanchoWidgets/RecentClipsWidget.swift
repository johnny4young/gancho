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

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Recent clips")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Spacer()
                Button(intent: SaveClipboardIntent()) {
                    Image(systemName: "square.and.arrow.down")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Save Clipboard")
            }
            if entry.clips.isEmpty {
                Spacer()
                Text("Nothing yet")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
            } else {
                ForEach(entry.clips) { clip in
                    Link(destination: clip.deepLinkURL ?? fallbackURL) {
                        HStack(spacing: 6) {
                            Image(systemName: Self.symbol(for: clip.kind))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text(clip.displayText)
                                .font(.caption2)
                                .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding(12)
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var fallbackURL: URL { URL(string: "gancho://")! }

    private static func symbol(for kind: ClipContentKind) -> String {
        switch kind {
        case .url: "link"
        case .image: "photo"
        case .color: "paintpalette"
        case .code, .json, .jwt: "curlybraces"
        case .email: "envelope"
        case .phoneNumber: "phone"
        case .secret, .creditCard: "lock.fill"
        case .fileReference: "doc"
        default: "doc.on.clipboard"
        }
    }
}

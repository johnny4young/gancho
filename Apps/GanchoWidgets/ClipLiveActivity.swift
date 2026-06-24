import ActivityKit
import GanchoKit
import SwiftUI
import WidgetKit

/// The "last clip ready to paste" Live Activity — Dynamic Island when the phone
/// is in use, a banner on the lock screen. Shows the clip (masked if sensitive),
/// its kind, and a glanceable sync badge. Tapping it opens the app.
struct ClipLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ClipActivityAttributes.self) { context in
            ClipActivityLockScreen(state: context.state)
                .activityBackgroundTint(Color(.systemBackground).opacity(0.6))
                .activitySystemActionForegroundColor(.primary)
        } dynamicIsland: { context in
            let state = context.state
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: state.isSensitive ? "lock.fill" : state.kindSymbolName)
                        .font(.title3)
                        .foregroundStyle(.tint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    SyncBadge(state.sync)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Ready to paste")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        Text(displayPreview(state))
                            .font(.callout)
                            .lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: "paperclip")
                    .foregroundStyle(.tint)
            } compactTrailing: {
                Image(systemName: state.sync.symbolName)
                    .foregroundStyle(syncColor(state.sync.emphasis))
            } minimal: {
                Image(systemName: "paperclip")
                    .foregroundStyle(.tint)
            }
            .widgetURL(URL(string: "gancho://"))
            .keylineTint(.accentColor)
        }
    }
}

/// Lock-screen / banner layout: kind icon, "Ready to paste" + the clip, badge.
private struct ClipActivityLockScreen: View {
    let state: ClipActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: state.isSensitive ? "lock.fill" : state.kindSymbolName)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 38, height: 38)
                .background(.tint.opacity(0.15), in: .rect(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text("Ready to paste")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(displayPreview(state))
                    .font(.callout)
                    .lineLimit(1)
                    .foregroundStyle(.primary)
            }
            Spacer(minLength: 0)
            SyncBadge(state.sync)
        }
        .padding(14)
    }
}

/// Icon-only sync indicator, colour-coded by emphasis. No text keeps it
/// glanceable and avoids per-state localization on this surface.
private struct SyncBadge: View {
    let badge: ClipSyncBadge
    init(_ badge: ClipSyncBadge) { self.badge = badge }

    var body: some View {
        Image(systemName: badge.symbolName)
            .font(.callout)
            .foregroundStyle(syncColor(badge.emphasis))
            .accessibilityHidden(true)
    }
}

private func displayPreview(_ state: ClipActivityAttributes.ContentState) -> String {
    state.isSensitive ? "•••" : state.preview
}

private func syncColor(_ emphasis: ClipSyncBadge.Emphasis) -> Color {
    switch emphasis {
    case .success: .green
    case .warning: .orange
    case .neutral: .secondary
    }
}

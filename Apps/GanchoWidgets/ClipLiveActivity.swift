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
                    HStack(spacing: 7) {
                        GanchoMark(size: 24)
                        if state.isSensitive {
                            Image(systemName: "lock.fill")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    SyncBadge(state.sync)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ready to paste")
                                .font(.caption2.bold())
                                .foregroundStyle(.secondary)
                            Text(displayPreview(state))
                                .font(.callout)
                                .lineLimit(2)
                        }
                        ClipActivityActions(state: state)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                GanchoMark(size: 20)
            } compactTrailing: {
                Image(systemName: state.sync.symbolName)
                    .foregroundStyle(syncColor(state.sync.emphasis))
            } minimal: {
                GanchoMark(size: 19)
            }
            .widgetURL(clipURL(state))
            .keylineTint(GanchoMark.green)
        }
    }
}

/// Lock-screen / banner layout: kind icon, "Ready to paste" + the clip, badge.
private struct ClipActivityLockScreen: View {
    let state: ClipActivityAttributes.ContentState

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                GanchoMark(size: 38)
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
            ClipActivityActions(state: state)
        }
        .padding(14)
    }
}

/// Copy again puts the clip back on the pasteboard; a protected clip never
/// offers it from here. Open goes to the clip in Gancho.
private struct ClipActivityActions: View {
    let state: ClipActivityAttributes.ContentState

    var body: some View {
        if let id = state.clipID {
            HStack(spacing: 8) {
                if !state.isSensitive {
                    Button(intent: CopyClipAgainIntent(clipID: id)) {
                        Label("Copy again", systemImage: "doc.on.doc")
                            .font(.footnote.weight(.bold))
                            .frame(maxWidth: .infinity, minHeight: 32)
                            .background(GanchoMark.green, in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(Color(red: 0.016, green: 0.129, blue: 0.051))
                    }
                    .buttonStyle(.plain)
                }
                Link(destination: clipURL(state)) {
                    Text("Open in Gancho")
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(.primary.opacity(0.14), in: RoundedRectangle(cornerRadius: 10))
                        .foregroundStyle(.primary)
                }
            }
        }
    }
}

private func clipURL(_ state: ClipActivityAttributes.ContentState) -> URL {
    state.clipID.flatMap(WidgetClips.deepLink(to:)) ?? URL(string: "gancho://")!
}

/// Gancho's mark — the real brand icon (the green tile + white hook from the
/// design system, `GanchoMark` in the asset catalog), so the activity reads as
/// the app in the Dynamic Island and lock screen instead of a generic system
/// clip. Scales with `size` for the pill, the expanded island, and the banner.
struct GanchoMark: View {
    var size: CGFloat = 22
    /// gancho brand green (#34C759 — Apple system green); used for the keyline.
    static let green = Color(red: 0.204, green: 0.780, blue: 0.349)

    var body: some View {
        Image("GanchoMark")
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
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

#if DEBUG
    private let previewLink = ClipActivityAttributes.ContentState(
        preview: "example.com/a/b?q=a&b", kindSymbolName: "link", isSensitive: false,
        sync: .synced, clipID: UUID())
    private let previewSecret = ClipActivityAttributes.ContentState(
        preview: "•••", kindSymbolName: "lock", isSensitive: true, sync: .synced, clipID: UUID())

    #Preview("Expanded", as: .dynamicIsland(.expanded), using: ClipActivityAttributes()) {
        ClipLiveActivity()
    } contentStates: {
        previewLink
        previewSecret
    }

    #Preview("Lock Screen", as: .content, using: ClipActivityAttributes()) {
        ClipLiveActivity()
    } contentStates: {
        previewLink
        previewSecret
    }
#endif

import AppIntents
import GanchoAppCore
import GanchoDesign
import GanchoKit
import SwiftUI
import WidgetKit

/// The large widget: six recent clips, board chips that scope them, the sync
/// age, and Save + Open. A protected row reads like the app's (kind, stored
/// mask, lock, time left) and never carries the secret.
struct RecentClipsLargeView: View {
    let entry: RecentClipsEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            header
            chips
                .padding(.top, 4)
                .padding(.bottom, 6)
            if entry.clips.isEmpty {
                Spacer()
                Image(systemName: "doc.on.clipboard")
                    .font(.title2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 8) {
                    ForEach(entry.clips.prefix(6)) { row($0) }
                }
            }
            Spacer(minLength: 0)
            actions
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Image("GanchoMarkTemplate")
                .resizable()
                .frame(width: 12, height: 12)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            Text("Gancho").font(.caption.bold())
            Spacer()
            if let synced = entry.syncedAt {
                Label {
                    Text(.currentDate, format: .reference(to: synced, maxFieldCount: 1))
                } icon: {
                    Image(systemName: "checkmark.icloud")
                }
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("widget-sync-age")
            }
        }
    }

    private var chips: some View {
        HStack(spacing: 5) {
            chip(Text("All"), board: nil)
            ForEach(entry.chips) { chip($0.displayTitle, board: $0) }
        }
        .privacySensitive()
    }

    private func chip(_ title: Text, board: Pinboard?) -> some View {
        let selected = entry.boardID == board?.id
        return Button(intent: ShowWidgetBoardIntent(boardID: board?.id)) {
            HStack(spacing: 4) {
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                } else if let board {
                    BoardIdentityMark(board: board, size: 8)
                }
                title.lineLimit(1)
            }
            .font(.system(size: 10.5, weight: .semibold))
            .padding(.horizontal, 7)
            .frame(height: 18)
            .background(
                selected
                    ? AnyShapeStyle(GanchoTokens.Palette.accent)
                    : AnyShapeStyle(.primary.opacity(0.07)),
                in: Capsule()
            )
            .foregroundStyle(
                selected
                    ? AnyShapeStyle(ContrastingForeground(on: GanchoTokens.Palette.accent))
                    : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
    }

    private func row(_ clip: WidgetClipEntry) -> some View {
        Link(destination: clip.deepLinkURL ?? URL(string: "gancho://")!) {
            HStack(spacing: 7) {
                tile(clip)
                if clip.isSensitive {
                    Text(clip.kind.cardName).font(.caption.weight(.semibold))
                    Text(verbatim: clip.maskedTail ?? clip.displayText)
                        .privacySensitive()
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                } else {
                    Text(verbatim: clip.displayText).font(.caption)
                }
                Spacer(minLength: 4)
                meta(clip)
            }
            .lineLimit(1)
            .frame(height: 22)
        }
    }

    private func tile(_ clip: WidgetClipEntry) -> some View {
        let tint = GanchoTokens.Palette.kindTint(for: clip.kind)
        return Image(systemName: clip.isSensitive ? "lock.fill" : clip.kind.symbolName)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(ReadableInk(base: tint))
            .frame(width: 20, height: 20)
            .background(
                tint.opacity(0.16), in: RoundedRectangle(cornerRadius: 5, style: .continuous)
            )
            .accessibilityHidden(true)
    }

    @ViewBuilder private func meta(_ clip: WidgetClipEntry) -> some View {
        Group {
            if clip.isSensitive, let expiry = clip.expiresAt, expiry > entry.date {
                Text(timerInterval: entry.date...expiry, countsDown: true)
                    .privacySensitive()
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 44, alignment: .trailing)
            } else if let created = clip.createdAt {
                let age = CompactAge(since: created, now: entry.date)
                if let app = clip.sourceAppBundleID {
                    Text("\(SourceApp.fallbackName(forBundleID: app)) · \(Text(age.widgetLabel))")
                } else {
                    Text(age.widgetLabel)
                }
            }
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
    }

    private var actions: some View {
        HStack(spacing: 6) {
            Button(intent: SaveClipboardIntent()) {
                Label("Save clipboard", systemImage: "arrow.down")
                    .font(.caption.weight(.bold))
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .background(
                        GanchoTokens.Palette.accent, in: RoundedRectangle(cornerRadius: 10)
                    )
                    .foregroundStyle(ContrastingForeground(on: GanchoTokens.Palette.accent))
            }
            .buttonStyle(.plain)
            Link(destination: URL(string: "gancho://")!) {
                Text("Open Gancho")
                    .font(.caption.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 30)
                    .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    .foregroundStyle(.primary)
            }
        }
    }
}

extension CompactAge {
    /// The age a widget row shows: "now", "7 min", "2 h", "3 d" or a date.
    fileprivate var widgetLabel: LocalizedStringKey {
        switch self {
        case .now: "now"
        case .minutes(let minutes): "\(minutes) min"
        case .hours(let hours): "\(hours) h"
        case .days(let days): "\(days) d"
        case .date(let date): "\(date.formatted(.dateTime.month(.abbreviated).day()))"
        }
    }
}

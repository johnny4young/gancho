import GanchoAppCore
import GanchoDesign
import GanchoKit
import SwiftUI

struct RetentionSettingsTab: View {
    @Environment(AppModel.self) private var model
    @State private var forgetWindow: ForgetRecentWindow = .fifteenMinutes
    @State private var forgettable = 0
    @State private var forgetRevision = 0

    var body: some View {
        @Bindable var model = model
        Form {
            Section {
                RetentionTimelineCard(policy: model.retentionPolicy)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            Section("History") {
                Picker("Keep history for", selection: $model.retentionPolicy.global) {
                    windowOptions
                }
                Picker(
                    "Images", selection: perKindBinding(.image)
                ) { windowOptionsWithDefault }
                .accessibilityIdentifier("retention-images-picker")
                Picker(
                    "Text", selection: perKindBinding(.text)
                ) { windowOptionsWithDefault }
                .accessibilityIdentifier("retention-text-picker")
                Text(
                    "A per-type limit overrides the global window. Pinned clips and boards never expire."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section("Sensitive items") {
                Picker(
                    "Sensitive items expire after",
                    selection: $model.retentionPolicy.sensitiveLifetime
                ) {
                    Text("5 minutes").tag(TimeInterval(300))
                    Text("10 minutes").tag(TimeInterval(600))
                    Text("30 minutes").tag(TimeInterval(1800))
                }
                Text(
                    // swiftlint:disable:next line_length
                    "Detected secrets — passwords, keys, cards — always follow this limit. A safety guard you can shorten but not extend."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }

            Section("Forget recent clips") {
                Picker("Copied in the last", selection: $forgetWindow) {
                    Text("5 minutes").tag(ForgetRecentWindow.fiveMinutes)
                    Text("15 minutes").tag(ForgetRecentWindow.fifteenMinutes)
                    Text("1 hour").tag(ForgetRecentWindow.hour)
                }
                .accessibilityIdentifier("forget-recent-window")
                HStack {
                    Text(forgettable == 0 ? "Nothing to forget" : "\(forgettable) clips")
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("forget-recent-count")
                    Spacer()
                    Button("Forget \(forgettable) clips", role: .destructive) {
                        Task {
                            _ = await model.forgetRecent(forgetWindow)
                            forgetRevision += 1
                        }
                    }
                    .disabled(forgettable == 0)
                    .accessibilityIdentifier("forget-recent-button")
                }
                Text(
                    "Pins, boards and snippets stay. Undo brings the clips back for a few seconds."
                )
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding(GanchoTokens.Spacing.md)
        .task(
            id: ForgetRefresh(
                window: forgetWindow, revision: forgetRevision,
                pending: model.pendingDeletionIDs.count)
        ) {
            forgettable = await model.forgettableClips(forgetWindow).count
        }
    }

    private struct ForgetRefresh: Equatable {
        let window: ForgetRecentWindow
        let revision: Int
        let pending: Int
    }

    @ViewBuilder private var windowOptions: some View {
        Text("24 hours").tag(RetentionPolicy.Window.day)
        Text("7 days").tag(RetentionPolicy.Window.week)
        Text("30 days").tag(RetentionPolicy.Window.month)
        Text("90 days").tag(RetentionPolicy.Window.quarter)
        Text("6 months").tag(RetentionPolicy.Window.halfYear)
        Text("1 year").tag(RetentionPolicy.Window.year)
        Text("Forever").tag(RetentionPolicy.Window.never)
    }

    @ViewBuilder private var windowOptionsWithDefault: some View {
        Text("Use global").tag(RetentionPolicy.Window?.none)
        Text("24 hours").tag(RetentionPolicy.Window?.some(.day))
        Text("7 days").tag(RetentionPolicy.Window?.some(.week))
        Text("30 days").tag(RetentionPolicy.Window?.some(.month))
        Text("90 days").tag(RetentionPolicy.Window?.some(.quarter))
        Text("6 months").tag(RetentionPolicy.Window?.some(.halfYear))
        Text("1 year").tag(RetentionPolicy.Window?.some(.year))
    }

    private func perKindBinding(_ kind: ClipContentKind) -> Binding<RetentionPolicy.Window?> {
        Binding(
            get: { model.retentionPolicy.perKind[kind] },
            set: { model.retentionPolicy.perKind[kind] = $0 })
    }
}

/// Every lifetime in one line, shortest first; a picker change moves its marker.
private struct RetentionTimelineCard: View {
    let policy: RetentionPolicy

    var body: some View {
        let markers = RetentionTimeline.markers(for: policy)
        VStack(alignment: .leading, spacing: 18) {
            GeometryReader { proxy in
                ZStack(alignment: .topLeading) {
                    Capsule().fill(.quaternary).frame(height: 3).offset(y: 6)
                    ForEach(Array(markers.enumerated()), id: \.offset) { index, marker in
                        let fraction = RetentionTimeline.position(of: index, in: markers.count)
                        markerView(marker, alignment: alignment(fraction))
                            .frame(width: 160, alignment: alignment(fraction))
                            .offset(x: offset(fraction, width: proxy.size.width))
                    }
                }
            }
            .frame(height: 36)
            Text(
                // swiftlint:disable:next line_length
                "Change a picker below and its marker moves. Older clips are deleted on this Mac and, when sync is on, on your other devices."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(.background, in: RoundedRectangle(cornerRadius: GanchoTokens.Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: GanchoTokens.Radius.md)
                .strokeBorder(.separator, lineWidth: GanchoTokens.Stroke.hairline)
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("retention-timeline")
    }

    private func alignment(_ fraction: Double) -> Alignment {
        fraction == 0 ? .leading : fraction == 1 ? .trailing : .center
    }

    /// The marker's frame starts where its label must sit for the dot to land on `fraction`.
    private func offset(_ fraction: Double, width: CGFloat) -> CGFloat {
        let x = width * fraction
        return fraction == 0 ? 0 : fraction == 1 ? x - 160 : x - 80
    }

    private func markerView(_ marker: RetentionTimeline.Marker, alignment: Alignment) -> some View {
        VStack(alignment: alignment.horizontal, spacing: 4) {
            Circle()
                .fill(color(marker))
                .frame(width: 16, height: 16)
                .overlay(Circle().strokeBorder(.background, lineWidth: 3))
                .overlay(Circle().strokeBorder(.separator, lineWidth: 1))
            Text(label(marker))
                .font(.caption2.weight(.bold))
                .foregroundStyle(ink(marker))
                .lineLimit(1)
                .fixedSize()
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("retention-marker")
    }

    private func label(_ marker: RetentionTimeline.Marker) -> String {
        let groups = marker.groups.map { group in
            switch group {
            case .secrets: String(localized: "secrets")
            case .images: String(localized: "images")
            case .text: String(localized: "text")
            case .everything: String(localized: "everything else")
            case .keptForever: String(localized: "pins, boards")
            }
        }
        return "\(Self.duration(marker.lifetime)) · \(groups.joined(separator: ", "))"
    }

    static func duration(_ lifetime: TimeInterval?) -> String {
        guard let lifetime else { return String(localized: "never") }
        let minutes = Int(lifetime / 60)
        if minutes < 60 { return String(localized: "\(minutes) min") }
        let days = Int(lifetime / 86_400)
        if days < 1 { return String(localized: "\(minutes / 60) h") }
        if days.isMultiple(of: 365) { return String(localized: "\(days / 365) y") }
        if days >= 180, days.isMultiple(of: 30) { return String(localized: "\(days / 30) mo") }
        return String(localized: "\(days) d")
    }

    private func color(_ marker: RetentionTimeline.Marker) -> Color {
        let first = marker.groups.first
        switch first {
        case .secrets: return GanchoTokens.Palette.danger
        case .images: return GanchoTokens.Palette.warning
        case .text: return Color.secondary
        case .everything: return GanchoTokens.Palette.success
        case .keptForever, nil: return Color.primary
        }
    }

    private func ink(_ marker: RetentionTimeline.Marker) -> AnyShapeStyle {
        switch marker.groups.first {
        case .secrets: AnyShapeStyle(GanchoTokens.Palette.danger)
        case .images: AnyShapeStyle(GanchoTokens.Palette.warningInk)
        case .text: AnyShapeStyle(.secondary)
        case .everything: AnyShapeStyle(GanchoTokens.Palette.accentInk)
        case .keptForever, nil: AnyShapeStyle(.primary)
        }
    }
}

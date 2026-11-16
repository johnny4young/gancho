import GanchoAppCore
import GanchoDesign
import GanchoKit
import SwiftUI

extension LibraryView {
    /// The scope's name and total, the sync state, and the scope's kind mix.
    var scopeHeader: some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.sm) {
            HStack(alignment: .firstTextBaseline, spacing: GanchoTokens.Spacing.sm) {
                scopeTitle
                    .panelFont(size: 52, design: .serif)
                    .foregroundStyle(GanchoTokens.Palette.ink)
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityIdentifier("library-title")
                if let total = visibleTotal {
                    Text(verbatim: "\(total)")
                        .panelFont(size: 20, design: .default)
                        .monospacedDigit()
                        .foregroundStyle(GanchoTokens.Palette.ink3)
                        .accessibilityLabel(Text("\(total) clips"))
                        .accessibilityValue(Text("\(total) clips"))
                        .accessibilityIdentifier("library-scope-count")
                }
                if case .board(let id) = selection, model.agentExposedBoardIDs.contains(id) {
                    ViewThatFits(in: .horizontal) {
                        AgentExposedBadge()
                        AgentExposedBadge(compact: true)
                    }
                    .accessibilityIdentifier("library-exposed-badge")
                }
                Spacer(minLength: 0)
                syncCaption
            }
            if !kindMix.isEmpty { LibraryKindMixBar(segments: kindMix) }
        }
        .padding(.horizontal, GanchoTokens.Spacing.md)
        .padding(.top, GanchoTokens.Spacing.sm)
        .padding(.bottom, GanchoTokens.Spacing.xs)
    }

    /// The scope's total less the clips hidden while their delete awaits Undo.
    private var visibleTotal: Int? {
        clipList.total.map { total in
            total - clipList.items.count { model.pendingDeletionIDs.contains($0.id) }
        }
    }

    /// Only scopes the store counts by kind have a mix: All clips and boards,
    /// less the clips hidden while their delete awaits Undo.
    private var kindMix: [KindMixCaption] {
        guard !clips.isEmpty else { return [] }
        var counts: [ClipContentKind: Int]
        switch selection ?? .allClips {
        case .allClips: counts = kindCounts
        case .board(let id): counts = boardKindCounts[id] ?? [:]
        case .pinned, .savedFilter, .snippet: return []
        }
        for clip in clipList.items where model.pendingDeletionIDs.contains(clip.id) {
            counts[clip.kind] = max(0, (counts[clip.kind] ?? 0) - 1)
        }
        return ClipKindFilter.captionedMix(of: counts)
    }

    @ViewBuilder private var syncCaption: some View {
        if case .upToDate = model.syncStatus {
            Label("Synced", systemImage: "checkmark")
                .panelFont(.caption2, design: .monospaced)
                .textCase(.uppercase)
                .tracking(1)
                .foregroundStyle(GanchoTokens.Palette.ink3)
                .accessibilityIdentifier("sync-status")
        } else {
            SyncStatusView(status: model.syncStatus)
        }
    }
}

/// A scope's kinds as one bar: each segment as wide as its share, the largest
/// brightest, captioned with its name and count.
struct LibraryKindMixBar: View {
    let segments: [KindMixCaption]

    private static let tones: [Double] = [0.92, 0.6, 0.42, 0.3, 0.22, 0.16]

    var body: some View {
        WeightedRowLayout(spacing: 3) {
            ForEach(Array(segments.enumerated()), id: \.offset) { index, segment in
                VStack(alignment: .leading, spacing: 6) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(
                            GanchoTokens.Palette.ink.opacity(
                                Self.tones[min(index, Self.tones.count - 1)])
                        )
                        .frame(height: 6)
                    HStack(spacing: 5) {
                        Self.name(segment.label)?.textCase(.uppercase).tracking(0.8)
                        Text(verbatim: "\(segment.count)")
                            .foregroundStyle(GanchoTokens.Palette.ink2)
                    }
                    .panelFont(.caption2, design: .monospaced)
                    .foregroundStyle(GanchoTokens.Palette.ink3)
                    .lineLimit(1)
                    .fixedSize()
                }
                .layoutWeight(Double(segment.count))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
        .accessibilityIdentifier("library-kind-mix")
    }

    private static func name(_ label: KindMixCaption.Label) -> Text? {
        switch label {
        case .filter(let filter): Text(filter.title)
        case .text: Text("Text")
        case .other: nil
        }
    }

    private var spokenLabel: Text {
        let parts = segments.map { segment in
            Self.name(segment.label).map { Text("\(segment.count) \($0)") }
                ?? Text("\(segment.count) other")
        }
        let list = parts.dropFirst().reduce(parts.first ?? Text(verbatim: "")) {
            Text("\($0), \($1)")
        }
        return Text("Kinds: \(list)")
    }
}

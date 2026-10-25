import GanchoAppCore
import GanchoDesign
import GanchoKit
import SwiftUI

/// A Library card: kind tile and title, a preview that says what the clip is
/// (a link's host, a colour's swatch, a secret's stored mask), the boards it
/// lives on and a `Kind · App · age` line. Protected clips never expose their
/// title or payload, and private mode shows kinds only.
struct LibraryClipCard: View {
    let clip: ClipItem
    var boards: [Pinboard] = []
    let thumbnails: GanchoDesign.ClipThumbnailStore
    let previewsHidden: Bool
    @State private var finishedLoading = false

    private var protected: Bool { ClipSafePresentation.requiresMasking(clip) }
    private var masked: Bool { previewsHidden || protected }

    var body: some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
            HStack(spacing: GanchoTokens.Spacing.xs) {
                ClipTile(
                    item: clip, size: 24, previewsHidden: masked,
                    thumbnail: masked ? nil : thumbnails.cached(for: clip)
                )
                .accessibilityHidden(true)
                title.lineLimit(1)
                Spacer(minLength: 0)
                if clip.isPinned {
                    Image(systemName: "pin.fill").panelFont(.caption2).foregroundStyle(.secondary)
                        .accessibilityLabel(Text("Pinned"))
                }
            }
            .panelFont(.callout, .bold)
            preview
                .frame(maxWidth: .infinity, minHeight: 88, maxHeight: 88, alignment: .topLeading)
                .background(.quaternary.opacity(0.35), in: previewShape)
                .clipShape(previewShape)
            if !boards.isEmpty { boardChips }
            metaLine
        }
        .padding(GanchoTokens.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.background.secondary, in: shape)
        .overlay(shape.strokeBorder(.separator, lineWidth: GanchoTokens.Stroke.hairline))
        .contentShape(shape)
        .task(id: masked ? nil : ClipContentVersion(clip)) {
            finishedLoading = false
            guard !masked, clip.kind == .image else { return }
            await thumbnails.ensureLoaded(clip)
            guard !Task.isCancelled else { return }
            finishedLoading = true
        }
        .accessibilityElement(children: .combine)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
    }

    private var previewShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: GanchoTokens.Radius.sm, style: .continuous)
    }

    @ViewBuilder private var title: some View {
        if masked || clip.title.isEmpty {
            Text(clip.kind.cardName)
        } else {
            Text(verbatim: clip.title)
        }
    }

    @ViewBuilder private var preview: some View {
        if previewsHidden {
            Text(verbatim: ClipSafePresentation.masked).foregroundStyle(.secondary).padding(8)
        } else if protected {
            secretPreview
        } else if clip.kind == .image {
            imagePreview
        } else if clip.kind == .color, let color = Color(hexString: clip.preview) {
            ZStack(alignment: .bottomLeading) {
                color
                Text(verbatim: clip.preview)
                    .panelFont(.caption2, design: .monospaced)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.black.opacity(0.35), in: RoundedRectangle(cornerRadius: 5))
                    .padding(6)
            }
        } else if clip.kind == .url, let link = ClipLinkParts(text: clip.preview) {
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: link.host).panelFont(.headline, .bold).lineLimit(1)
                if let path = link.path {
                    Text(verbatim: path)
                        .panelFont(.caption, design: .monospaced)
                        .foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .padding(8)
        } else if clip.kind == .code || clip.kind == .json {
            Text(GanchoTokens.Syntax.highlighted(String(clip.preview.prefix(240))))
                .panelFont(.caption, design: .monospaced)
                .lineLimit(4).padding(8)
        } else {
            Text(verbatim: ByteSize.humanizedPreview(clip.preview))
                .panelFont(.caption).foregroundStyle(.secondary)
                .lineLimit(4).padding(8)
        }
    }

    /// The stored mask only, with its countdown while it is about to expire.
    private var secretPreview: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(verbatim: ClipSafePresentation.maskedTail(for: clip))
                .panelFont(.callout, .bold, design: .monospaced)
            if clip.expiresAt != nil {
                TimelineView(.periodic(from: .now, by: 15)) { context in
                    if let expiresAt = clip.expiresAt,
                        ClipCard.showsExpiryCountdown(expiresAt: expiresAt, now: context.date)
                    {
                        HStack(spacing: 4) {
                            Image(systemName: "timer")
                            Text("expires in \(Text(expiresAt, style: .timer))")
                        }
                        .panelFont(.caption2, digits: true)
                        .foregroundStyle(GanchoTokens.Palette.warningInk)
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(GanchoTokens.Palette.danger.opacity(0.05))
        .overlay(
            previewShape.strokeBorder(
                GanchoTokens.Palette.danger.opacity(0.3),
                style: StrokeStyle(lineWidth: 1, dash: [4]))
        )
    }

    @ViewBuilder private var imagePreview: some View {
        if let thumbnail = thumbnails.cached(for: clip) {
            thumbnail.resizable().scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
                .accessibilityLabel("Image preview")
        } else if finishedLoading {
            Label("Preview unavailable", systemImage: "photo")
                .panelFont(.caption).foregroundStyle(.secondary).padding(8)
        } else {
            ProgressView().controlSize(.small).accessibilityLabel("Loading preview")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var boardChips: some View {
        HStack(spacing: 4) {
            ForEach(boards) { board in
                HStack(spacing: 4) {
                    BoardIdentityMark(board: board, size: 8)
                    board.displayTitle.lineLimit(1)
                }
                .panelFont(.caption2, .semibold)
                .padding(.horizontal, 6).frame(height: 18)
                .background(.quaternary.opacity(0.6), in: Capsule())
            }
        }
        .foregroundStyle(.secondary)
    }

    /// `Kind · App · age`; an image says its format and size instead of its
    /// kind. Private mode keeps the kind only.
    private var metaLine: some View {
        HStack(spacing: 4) {
            if !masked, let info = clip.imageInfo {
                Text(verbatim: info.rowDetail(titled: true))
            } else {
                Text(clip.kind.cardName)
            }
            if !previewsHidden {
                if let bundleID = clip.sourceAppBundleID, !bundleID.isEmpty {
                    Text(verbatim: "·").accessibilityHidden(true)
                    Text(SourceApp.fallbackName(forBundleID: bundleID)).lineLimit(1)
                }
                Text(verbatim: "·").accessibilityHidden(true)
                // Minute-granular, like the panel row: the age moves while the window stays open.
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text(CompactAge(since: clip.createdAt, now: context.date).label)
                }
            }
        }
        .panelFont(.caption2)
        .foregroundStyle(.secondary)
    }
}

extension CompactAge {
    var label: LocalizedStringKey {
        switch self {
        case .now: "now"
        case .minutes(let minutes): "\(minutes) min"
        case .hours(let hours): "\(hours) h"
        case .days(let days): "\(days) d"
        case .date(let date): "\(date.formatted(.dateTime.month(.abbreviated).day()))"
        }
    }
}

/// Tracks the pointer over a card; hover is cleared while the list scrolls.
struct LibraryCardHover<Content: View>: View {
    @ViewBuilder let content: (Bool) -> Content
    @State private var hovering = false
    @Environment(\.listIsScrolling) private var listIsScrolling

    var body: some View {
        content(hovering)
            .onHover {
                hovering = ClipCard.hoverState(pointerInside: $0, listIsScrolling: listIsScrolling)
            }
            .onChange(of: listIsScrolling) { _, scrolling in
                hovering = ClipCard.hoverState(pointerInside: hovering, listIsScrolling: scrolling)
            }
    }
}

import GanchoAppCore
import GanchoDesign
import GanchoKit
import SwiftUI

/// A Library card: the clip at its natural shape (a colour as its swatch, an
/// image at its own proportions, a link host-first, prose as prose, code in a
/// well) over its title and a quiet `App · age` line. Protected clips show the
/// stored mask only, and private mode shows kinds only.
struct LibraryClipCard: View {
    let clip: ClipItem
    var boards: [Pinboard] = []
    let thumbnails: GanchoDesign.ClipThumbnailStore
    let previewsHidden: Bool
    /// A grid of equal cells fixes the specimen's height; nil lets it run.
    var specimenHeight: CGFloat?
    var sensitiveLifetime: TimeInterval?
    @State private var finishedLoading = false
    @Environment(\.colorScheme) private var colorScheme

    private static let inset: CGFloat = 12

    private var protected: Bool { ClipSafePresentation.requiresMasking(clip) }
    private var masked: Bool { previewsHidden || protected }
    private var content: ClipRowContent {
        ClipRowContent(
            item: clip, masking: previewsHidden ? .hidden : protected ? .storedMask : .none)
    }
    private var title: String { clip.title.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var isProse: Bool { clip.kind == .text || clip.kind == .richText }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            specimen
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: specimenHeight, alignment: .topLeading)
                .clipped()
            footer
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(GanchoTokens.Palette.controlFill, in: shape)
        .clipShape(shape)
        .overlay(
            shape.strokeBorder(
                GanchoTokens.Palette.hairline, lineWidth: GanchoTokens.Stroke.hairline)
        )
        .contentShape(shape)
        .task(id: masked ? nil : ClipContentVersion(clip)) {
            finishedLoading = false
            guard !masked, clip.kind == .image else { return }
            await thumbnails.ensureLoaded(clip)
            guard !Task.isCancelled else { return }
            finishedLoading = true
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
    }

    // MARK: - Specimen

    @ViewBuilder private var specimen: some View {
        if !masked, clip.kind == .image {
            imageSpecimen
        } else if !masked, clip.kind == .color, let value = ColorValue.parse(clip.preview) {
            swatch(Color(Color.Resolved(value)))
        } else {
            switch content.headline {
            case .link(let host, let path):
                VStack(alignment: .leading, spacing: 0) {
                    Text(verbatim: host).panelFont(size: 20, .semibold)
                        .foregroundStyle(GanchoTokens.Palette.ink).lineLimit(1)
                    if let path {
                        Text(verbatim: path).panelFont(size: 20)
                            .foregroundStyle(GanchoTokens.Palette.ink3).lineLimit(2)
                    }
                }
                .truncationMode(.middle)
                .padding([.top, .horizontal], Self.inset)
            case .code:
                Text(GanchoTokens.Syntax.tonal(String(clip.preview.prefix(480))))
                    .panelFont(.caption, design: .monospaced)
                    .lineLimit(9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Self.inset)
                    .background(Color.black.opacity(colorScheme == .dark ? 0.22 : 0.05))
            case .value(let value):
                HStack(spacing: GanchoTokens.Spacing.xs) {
                    if let countdown = Countdown(item: clip, lifetime: sensitiveLifetime) {
                        TimeRing(countdown).frame(width: 16, height: 16)
                    }
                    Text(verbatim: value).panelFont(.callout, .medium, design: .monospaced)
                        .foregroundStyle(GanchoTokens.Palette.ink).lineLimit(2)
                }
                .padding([.top, .horizontal], Self.inset)
            case .text(let text):
                prose(isProse && !masked ? bodyText : text)
            case .kindName(let kind):
                Text(kind.cardName).panelFont(.callout)
                    .foregroundStyle(GanchoTokens.Palette.ink2)
                    .padding([.top, .horizontal], Self.inset)
            }
        }
    }

    private var bodyText: String {
        ByteSize.humanizedPreview(clip.preview).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Short prose reads as a quotation; longer text as interface text. The
    /// bottom fades when capture stored only the start of the clip.
    private func prose(_ text: String) -> some View {
        let short = text.count <= 90 && text.split(whereSeparator: \.isNewline).count <= 3
        let cut = clip.preview.count >= ClipRowContent.storedPreviewLimit
        return Text(verbatim: text)
            .panelFont(size: short ? 20 : 13, design: short ? .serif : .default)
            .foregroundStyle(short ? GanchoTokens.Palette.ink : GanchoTokens.Palette.ink2)
            .lineLimit(short ? 5 : 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding([.top, .horizontal], Self.inset)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: cut ? 0.55 : 1),
                        .init(color: .black.opacity(cut ? 0.2 : 1), location: 1)
                    ], startPoint: .top, endPoint: .bottom)
            }
    }

    /// The colour itself, with its own notation in an ink that reads on it.
    private func swatch(_ color: Color) -> some View {
        let notation = bodyText.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        return
            color
            .frame(height: specimenHeight ?? 112)
            .overlay(alignment: .bottomLeading) {
                Text(verbatim: notation)
                    .panelFont(size: 17, .medium, design: .monospaced)
                    .foregroundStyle(ContrastingForeground(on: color))
                    .lineLimit(1)
                    .padding(Self.inset)
            }
    }

    /// The height an image takes at the narrowest column, from its recorded
    /// proportions. Independent of the card's real width, so a scroller that
    /// narrows the wall never changes its height.
    nonisolated static func imageHeight(for info: ClipImageInfo?) -> CGFloat {
        guard let info, info.width > 0, info.height > 0 else { return 140 }
        return min(max(210 * CGFloat(info.height) / CGFloat(info.width), 96), 260)
    }

    private var imageSpecimen: some View {
        Color.clear
            .frame(height: specimenHeight ?? Self.imageHeight(for: clip.imageInfo))
            .overlay {
                if let thumbnail = thumbnails.cached(for: clip) {
                    thumbnail.resizable().scaledToFill()
                } else if finishedLoading {
                    Label("Preview unavailable", systemImage: "photo")
                        .panelFont(.caption).foregroundStyle(GanchoTokens.Palette.ink3)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .clipped()
    }

    // MARK: - Footer

    /// The clip's name; its kind when it has none to show.
    private var footerTitle: Text? {
        if masked { return Text(clip.kind.cardName) }
        if !title.isEmpty { return Text(verbatim: title) }
        return clip.kind == .image || specimenHeight != nil ? Text(clip.kind.cardName) : nil
    }

    /// What the specimen does not already say: an image's facts, a code
    /// clip's kind and length, any other kind's name.
    private var facts: [Text] {
        guard !masked else { return [] }
        switch clip.kind {
        case .text, .richText, .color, .url: return []
        case .image: return content.details.map(Self.text(for:))
        default:
            let lines = content.details.filter { if case .lines = $0 { true } else { false } }
            return [Text(clip.kind.cardName)] + lines.map(Self.text(for:))
        }
    }

    private var sourceName: String? {
        guard !previewsHidden, let bundleID = clip.sourceAppBundleID, !bundleID.isEmpty
        else { return nil }
        return SourceApp.fallbackName(forBundleID: bundleID)
    }

    private static func text(for detail: ClipRowContent.Detail) -> Text {
        switch detail {
        case .verbatim(let text): Text(verbatim: text)
        case .lines(let count): Text("\(count) lines")
        case .kindName(let kind): Text(kind.cardName)
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: GanchoTokens.Spacing.xs) {
                if let footerTitle {
                    footerTitle.panelFont(.callout, .medium)
                        .foregroundStyle(GanchoTokens.Palette.ink).lineLimit(1)
                } else {
                    metaLine
                }
                Spacer(minLength: 0)
                if clip.isPinned {
                    Image(systemName: "pin.fill").panelFont(.caption2)
                        .foregroundStyle(GanchoTokens.Palette.ink3)
                }
            }
            if !boards.isEmpty { boardChips }
            if footerTitle != nil, !previewsHidden { metaLine }
        }
        .padding(.horizontal, Self.inset)
        .padding(.vertical, 10)
    }

    private var boardChips: some View {
        HStack(spacing: 4) {
            ForEach(boards) { board in
                HStack(spacing: 4) {
                    BoardIdentityMark(board: board, size: 8)
                    board.displayTitle.lineLimit(1)
                }
                .panelFont(.caption2, .medium)
                .padding(.horizontal, 6).frame(height: 18)
                .overlay(
                    Capsule().strokeBorder(
                        GanchoTokens.Palette.hairline, lineWidth: GanchoTokens.Stroke.hairline))
            }
        }
        .foregroundStyle(GanchoTokens.Palette.ink2)
    }

    /// `facts · App · age`. Private mode keeps the kind only, in the title.
    private var metaLine: some View {
        let parts = facts + (sourceName.map { [Text(verbatim: $0)] } ?? [])
        return HStack(spacing: 4) {
            ForEach(parts.indices, id: \.self) { index in
                parts[index].lineLimit(1)
                Text(verbatim: "·")
            }
            if !previewsHidden {
                // Minute-granular, like the panel row: the age moves while the window stays open.
                TimelineView(.periodic(from: .now, by: 60)) { context in
                    Text(CompactAge(since: clip.createdAt, now: context.date).label)
                }
            }
        }
        .panelFont(.caption, digits: true)
        .foregroundStyle(GanchoTokens.Palette.ink3)
    }

    // MARK: - Accessibility

    /// One label, name first: the specimen reads in a different order than it
    /// looks, and a protected clip says its mask and nothing more.
    private var spokenLabel: Text {
        var parts = [footerTitle ?? Text(clip.kind.cardName)]
        switch content.headline {
        case .link(let host, let path): parts.append(Text(verbatim: host + (path ?? "")))
        case .value(let text), .code(let text): parts.append(Text(verbatim: text))
        case .text(let text): parts.append(Text(verbatim: isProse && !masked ? bodyText : text))
        case .kindName: break
        }
        if !masked, clip.kind == .image {
            parts.append(
                thumbnails.cached(for: clip) != nil
                    ? Text("Image preview")
                    : finishedLoading ? Text("Preview unavailable") : Text("Loading preview"))
        }
        if clip.isPinned { parts.append(Text("Pinned")) }
        parts += boards.map(\.displayTitle) + facts
        if let sourceName { parts.append(Text(verbatim: sourceName)) }
        return parts.dropFirst().reduce(parts[0]) { Text("\($0), \($1)") }
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

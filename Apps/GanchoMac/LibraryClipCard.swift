import GanchoDesign
import GanchoKit
import SwiftUI

/// A visual label for the existing Library copy button. Only cached, bounded
/// thumbnails enter rendering; protected clips never expose titles or payloads.
struct LibraryClipCard: View {
    let clip: ClipItem
    let thumbnails: GanchoDesign.ClipThumbnailStore
    let previewsHidden: Bool
    @State private var finishedLoading = false

    private var masked: Bool { previewsHidden || ClipSafePresentation.requiresMasking(clip) }

    var body: some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
            HStack {
                Image(systemName: masked ? "lock.fill" : clip.kind.symbolName)
                    .foregroundStyle(GanchoTokens.Palette.kindTint(for: clip.kind))
                if masked {
                    Text(verbatim: ClipSafePresentation.masked)
                } else if clip.title.isEmpty {
                    Text(LocalizedStringKey(clip.kind.rawValue))
                } else {
                    Text(verbatim: clip.title).lineLimit(1)
                }
                Spacer(minLength: 0)
                if clip.isPinned { Image(systemName: "pin.fill").font(.caption2) }
            }
            .font(.callout.weight(.semibold))
            preview
                .frame(maxWidth: .infinity, minHeight: 112, maxHeight: 112, alignment: .topLeading)
        }
        .padding(GanchoTokens.Spacing.sm)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(.background.secondary, in: shape)
        .overlay(shape.strokeBorder(.separator, lineWidth: GanchoTokens.Stroke.hairline))
        .contentShape(shape)
        .task(id: masked) {
            guard !masked, clip.kind == .image else { return }
            await thumbnails.ensureLoaded(clip)
            finishedLoading = true
        }
        .accessibilityElement(children: .combine)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
    }

    @ViewBuilder private var preview: some View {
        if masked {
            Text(verbatim: ClipSafePresentation.masked).foregroundStyle(.secondary)
        } else if clip.kind == .image {
            if let thumbnail = thumbnails.cached(for: clip.id) {
                thumbnail.resizable().scaledToFit()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .accessibilityLabel("Image preview")
            } else if finishedLoading {
                Label("Preview unavailable", systemImage: "photo")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ProgressView().controlSize(.small).accessibilityLabel("Loading preview")
            }
        } else if clip.kind == .color, let color = Color(hexString: clip.preview) {
            VStack(alignment: .leading, spacing: 5) {
                RoundedRectangle(cornerRadius: 5).fill(color)
                    .overlay(
                        RoundedRectangle(cornerRadius: 5).strokeBorder(.separator, lineWidth: 1))
                Text(verbatim: clip.preview).font(.caption.monospaced())
            }
        } else {
            Text(verbatim: ByteSize.humanizedPreview(clip.preview))
                .font(clip.kind == .code ? .system(.caption, design: .monospaced) : .caption)
                .foregroundStyle(.secondary).lineLimit(5)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

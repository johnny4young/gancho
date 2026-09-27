import GanchoDesign
import GanchoKit
import SwiftUI

/// The gallery's cell: the Library's visual card with the panel's selection
/// ring and ⌘N badge, exposed to accessibility exactly like a list row so
/// selection, quick-paste and the UI tests read the same either way.
struct PanelGalleryCard: View {
    let item: ClipItem
    let isSelected: Bool
    let previewsHidden: Bool
    let shortcutNumber: Int?
    let thumbnails: GanchoDesign.ClipThumbnailStore

    private var masked: Bool { previewsHidden || ClipSafePresentation.requiresMasking(item) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
        LibraryClipCard(clip: item, thumbnails: thumbnails, previewsHidden: previewsHidden)
            .overlay {
                if isSelected {
                    shape.fill(GanchoTokens.Palette.accent.opacity(0.08))
                        .allowsHitTesting(false)
                }
            }
            .overlay(
                shape.strokeBorder(
                    isSelected ? AnyShapeStyle(GanchoTokens.Palette.accent) : AnyShapeStyle(.clear),
                    lineWidth: 2)
            )
            .overlay(alignment: .topTrailing) {
                if let shortcutNumber, (1...9).contains(shortcutNumber) {
                    Text(verbatim: "⌘\(shortcutNumber)")
                        .font(.caption2.weight(.medium).monospaced())
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, GanchoTokens.Spacing.xxs)
                        .padding(.vertical, 1)
                        .background(
                            .quaternary,
                            in: RoundedRectangle(
                                cornerRadius: GanchoTokens.Radius.sm, style: .continuous)
                        )
                        .padding(GanchoTokens.Spacing.xs)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(shape)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityDescription)
            .accessibilityValue(
                shortcutNumber.map { Text(verbatim: "⌘\($0)") } ?? Text(verbatim: "")
            )
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier("clip-row")
    }

    /// Kind + preview, masked when the row is; the same phrase the list uses.
    private var accessibilityDescription: Text {
        let preview = masked ? "•••" : ByteSize.humanizedPreview(item.preview)
        return Text("\(Text(LocalizedStringKey(item.kind.rawValue))), \(preview)")
    }
}

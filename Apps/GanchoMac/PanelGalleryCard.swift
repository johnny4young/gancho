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
    var sensitiveLifetime: TimeInterval?

    private var masked: Bool { previewsHidden || ClipSafePresentation.requiresMasking(item) }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
        LibraryClipCard(
            clip: item, thumbnails: thumbnails, previewsHidden: previewsHidden,
            specimenHeight: 96, sensitiveLifetime: sensitiveLifetime
        )
        .overlay {
            if isSelected {
                shape.fill(GanchoTokens.Palette.selectionWash)
                    .allowsHitTesting(false)
            }
        }
        .overlay(
            shape.strokeBorder(
                isSelected ? AnyShapeStyle(GanchoTokens.Palette.ink) : AnyShapeStyle(.clear),
                lineWidth: 2)
        )
        // Over the free trailing end of the meta line.
        .overlay(alignment: .bottomTrailing) {
            if let shortcutNumber {
                ClipShortcutBadge(number: shortcutNumber)
                    .padding(GanchoTokens.Spacing.xs)
            }
        }
        .contentShape(shape)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text.clipRowDescription(for: item, masked: masked))
        .accessibilityValue(
            shortcutNumber.map { Text(verbatim: "⌘\($0)") } ?? Text(verbatim: "")
        )
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("clip-row")
    }
}

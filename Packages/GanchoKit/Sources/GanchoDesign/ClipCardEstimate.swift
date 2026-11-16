import Foundation
import GanchoKit

/// How tall a Library card will be, from what the row already holds. The wall
/// deals cards into columns before any of them is laid out, so the estimate
/// only has to rank them; fixed parts are exact, wrapped text is approximate.
public enum ClipCardEstimate {
    public static let swatchHeight: CGFloat = 112

    /// The height an image takes at the narrowest column, from its recorded
    /// proportions. Independent of the card's real width, so a scroller that
    /// narrows the wall never changes its height.
    public static func imageHeight(for info: ClipImageInfo?) -> CGFloat {
        guard let info, info.width > 0, info.height > 0 else { return 140 }
        let height =
            MasonryLayout.defaultMinColumnWidth * CGFloat(info.height) / CGFloat(info.width)
        return min(max(height, 96), 260)
    }

    public static func height(
        of item: ClipItem, columnWidth: CGFloat, previewsHidden: Bool = false,
        hasBoards: Bool = false
    ) -> CGFloat {
        let protected = ClipSafePresentation.requiresMasking(item)
        let masked = previewsHidden || protected
        let titled =
            masked || item.kind == .image
            || !item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // Padding, then a title line over the meta line, or the meta line alone.
        let footer: CGFloat = previewsHidden ? 37 : titled ? 56 : 35
        return specimen(of: item, columnWidth: columnWidth, hidden: previewsHidden, protected)
            + footer + (hasBoards ? 22 : 0)
    }

    private static func specimen(
        of item: ClipItem, columnWidth: CGFloat, hidden: Bool, _ protected: Bool
    ) -> CGFloat {
        if hidden { return 37 }
        if protected { return 32 }
        switch item.kind {
        case .image: return imageHeight(for: item.imageInfo)
        case .color where ColorValue.parse(item.preview) != nil: return swatchHeight
        case .text, .richText:
            return prose(ByteSize.humanizedPreview(item.preview), columnWidth: columnWidth)
        default: break
        }
        switch ClipRowContent(item: item).headline {
        case .link(_, let path): return path == nil ? 36 : 60
        case .code:
            let lines = item.preview.split(
                omittingEmptySubsequences: false, whereSeparator: \.isNewline
            ).count
            return 24 + CGFloat(min(max(lines, 1), 9)) * 15
        case .value: return 32
        case .text(let text): return prose(text, columnWidth: columnWidth)
        case .kindName: return 30
        }
    }

    /// Short prose is set large (five lines at most), longer text small (eight).
    static func prose(_ text: String, columnWidth: CGFloat) -> CGFloat {
        let paragraphs = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isNewline)
        let short = text.count <= 90 && paragraphs.count <= 3
        let perLine = max(1, Int((columnWidth - 24) / (short ? 9.5 : 6.8)))
        let lines = paragraphs.reduce(0) { $0 + max(1, ($1.count + perLine - 1) / perLine) }
        return 12 + CGFloat(min(max(lines, 1), short ? 5 : 8)) * (short ? 25 : 17)
    }
}

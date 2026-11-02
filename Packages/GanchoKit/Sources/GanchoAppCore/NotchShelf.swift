import ClipboardCore
import CoreGraphics
import Foundation

/// Where the notch shelf sits on one screen, in screen points (origin bottom-left).
public enum NotchShelfGeometry {
    /// A screen without a notch gets a zone this wide at the top center.
    public static let virtualZoneWidth: CGFloat = 200
    static let screenMargin: CGFloat = 8

    /// The camera housing, from the safe-area top inset and the widths of the
    /// two unobscured top corners; nil on a screen without one.
    public static func notch(
        in screen: CGRect, safeAreaTop: CGFloat, leftAreaWidth: CGFloat?,
        rightAreaWidth: CGFloat?
    ) -> CGRect? {
        guard safeAreaTop > 0, let leftAreaWidth, let rightAreaWidth else { return nil }
        let width = screen.width - leftAreaWidth - rightAreaWidth
        guard width > 0 else { return nil }
        return CGRect(
            x: screen.minX + leftAreaWidth, y: screen.maxY - safeAreaTop, width: width,
            height: safeAreaTop)
    }

    /// The notch itself, or a menu-bar-high strip at the top center.
    public static func dropZone(
        in screen: CGRect, notch: CGRect?, menuBarHeight: CGFloat
    )
        -> CGRect
    {
        if let notch { return notch }
        return CGRect(
            x: screen.midX - virtualZoneWidth / 2, y: screen.maxY - menuBarHeight,
            width: virtualZoneWidth, height: menuBarHeight)
    }

    /// The shelf hangs from the zone, centered under it and kept on screen.
    public static func shelf(size: CGSize, below zone: CGRect, in screen: CGRect) -> CGRect {
        let centered = zone.midX - size.width / 2
        let x = min(
            max(centered, screen.minX + screenMargin), screen.maxX - screenMargin - size.width)
        return CGRect(x: x, y: zone.minY - size.height, width: size.width, height: size.height)
    }
}

/// Tells a drag from a click with two content-free signals: the drag
/// pasteboard's change count, which a new drag bumps, and the mouse button.
public struct DragSessionWatch: Sendable {
    private var baseline: Int?

    public init() {}

    /// True while a drag that began after the last release is in progress.
    public mutating func sample(changeCount: Int, isMouseDown: Bool) -> Bool {
        guard isMouseDown, let baseline else {
            baseline = changeCount
            return false
        }
        return changeCount != baseline
    }
}

/// A place on the shelf that takes a drop.
public enum NotchShelfTarget: Hashable, Sendable {
    case board(UUID)
    case extractText
    case resize
    case stripLocation
    case newBoard

    public var needsImage: Bool {
        switch self {
        case .extractText, .resize, .stripLocation: true
        case .board, .newBoard: false
        }
    }
}

/// What the shelf accepts, decided from the drag's type list alone: nothing
/// is read until a drop lands.
public enum NotchShelfDrop {
    static let imageTypes: Set<String> = [
        "public.png", "public.tiff", "public.jpeg", "public.heic", "public.image"
    ]
    static let fileURLType = "public.file-url"
    static let supportedTypes: Set<String> = imageTypes.union([
        fileURLType, BoardDrop.clipReferenceType, "public.utf8-plain-text", "NSStringPboardType",
        "public.url", "public.rtf", "public.html"
    ])

    /// Never a password manager's concealed, transient or generated content.
    public static func accepts(types: Set<String>) -> Bool {
        types.isDisjoint(with: SensitivePasteboardTypes.captureVeto)
            && !types.isDisjoint(with: supportedTypes)
    }

    /// Image bytes, or a file that may be an image.
    public static func mayBeImage(types: Set<String>) -> Bool {
        !types.isDisjoint(with: imageTypes.union([fileURLType]))
    }

    /// The target under `point`, unless it needs an image the drag can't be.
    public static func target(
        at point: CGPoint, in frames: [NotchShelfTarget: CGRect], types: Set<String>
    ) -> NotchShelfTarget? {
        guard let hit = frames.first(where: { $0.value.contains(point) })?.key else { return nil }
        return !hit.needsImage || mayBeImage(types: types) ? hit : nil
    }
}

import GanchoKit

/// The history's type-filter rail (the design's All / Links / Code / Colors /
/// Images / Secrets pills). Pure data + matching so `PanelSearchModel` (and its
/// tests) can narrow results without importing SwiftUI — the localized `title`
/// lives in a shell-side extension.
public enum ClipKindFilter: String, CaseIterable, Identifiable, Sendable {
    case all, links, code, colors, images, secrets
    public var id: String { rawValue }

    /// The clip kind whose tint colours the pill's dot (nil for All).
    public var tintKind: ClipContentKind? {
        switch self {
        case .all: nil
        case .links: .url
        case .code: .code
        case .colors: .color
        case .images: .image
        case .secrets: .secret
        }
    }

    /// The kinds this pill keeps (nil for All), so a store can filter in SQL.
    public var kinds: Set<ClipContentKind>? {
        switch self {
        case .all: nil
        case .links: [.url]
        case .code: [.code, .json, .uuid]
        case .colors: [.color]
        case .images: [.image]
        case .secrets: [.secret, .jwt, .creditCard]
        }
    }

    public func matches(_ kind: ClipContentKind) -> Bool {
        kinds?.contains(kind) ?? true
    }

    /// How many clips this filter keeps, from per-kind counts.
    public func count(in perKind: [ClipContentKind: Int]) -> Int {
        perKind.reduce(0) { total, entry in matches(entry.key) ? total + entry.value : total }
    }
}

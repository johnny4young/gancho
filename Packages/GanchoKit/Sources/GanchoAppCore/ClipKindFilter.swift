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

    public func matches(_ kind: ClipContentKind) -> Bool {
        switch self {
        case .all: true
        case .links: kind == .url
        case .code: kind == .code || kind == .json || kind == .uuid
        case .colors: kind == .color
        case .images: kind == .image
        case .secrets: kind == .secret || kind == .jwt || kind == .creditCard
        }
    }
}

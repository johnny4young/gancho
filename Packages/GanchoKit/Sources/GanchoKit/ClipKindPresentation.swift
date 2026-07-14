import Foundation

/// Presentation facts per kind, framework-neutral (plain SF Symbol names so
/// the mapping is testable without SwiftUI). The panel renders these into
/// the distinctive icon + preview per type; sensitive kinds additionally
/// demand a masked preview by default.
extension ClipContentKind {
    /// SF Symbol for list rows and badges.
    public var symbolName: String {
        switch self {
        case .text: "text.alignleft"
        case .richText: "textformat"
        case .url: "link"
        case .email: "envelope"
        case .phoneNumber: "phone"
        case .color: "paintpalette"
        case .jwt: "key.horizontal"
        case .json: "curlybraces"
        case .uuid: "number"
        case .code: "chevron.left.forwardslash.chevron.right"
        case .creditCard: "creditcard"
        case .image: "photo"
        case .fileReference: "doc"
        case .address: "mappin.and.ellipse"
        case .date: "calendar"
        case .trackingNumber: "shippingbox"
        case .secret: "lock.fill"
        }
    }

    /// Kinds whose previews are masked by default (●●●● + last 4); revealing
    /// requires explicit interaction.
    public var prefersMaskedPreview: Bool {
        switch self {
        case .secret, .creditCard, .jwt: true
        default: false
        }
    }

    /// Kinds a user must never text-edit: structured/binary payloads (a color
    /// swatch, an image, a file reference have no free-text body) and EVERY
    /// masked-preview kind — editing would reveal a secret/card/JWT that a bare
    /// `isSensitive` check misses (a lone JWT classifies as `.jwt` but is not
    /// flagged sensitive). Single source of truth for the editability guards
    /// and the authoritative `updateClipText` SQL predicate.
    public static let textEditingRejectedKinds: [ClipContentKind] =
        [.image, .fileReference, .color] + allCases.filter(\.prefersMaskedPreview)

    /// True when a text editor may open this kind's content for editing. The
    /// caller still checks `isSensitive` and that the payload is actually text.
    public var allowsTextEditing: Bool {
        !Self.textEditingRejectedKinds.contains(self)
    }
}

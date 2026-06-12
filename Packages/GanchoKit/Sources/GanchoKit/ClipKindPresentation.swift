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
}

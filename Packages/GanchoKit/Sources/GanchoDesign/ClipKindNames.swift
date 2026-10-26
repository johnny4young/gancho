import GanchoKit
import SwiftUI

extension ClipContentKind {
    /// The kind as a card names it ("Link", "Secret"), capitalized for a title.
    public var cardName: LocalizedStringKey {
        switch self {
        case .text: "Text"
        case .richText: "Rich text"
        case .url: "Link"
        case .email: "Email"
        case .phoneNumber: "Phone number"
        case .color: "Color"
        case .jwt: "JWT"
        case .json: "JSON"
        case .uuid: "UUID"
        case .code: "Code"
        case .creditCard: "Card number"
        case .image: "Image"
        case .fileReference: "File"
        case .address: "Address"
        case .date: "Date"
        case .trackingNumber: "Tracking number"
        case .secret: "Secret"
        }
    }
}

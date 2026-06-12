/// What a captured clip *is*. Detected by the tier-0 classifier (GanchoAI)
/// at capture time; drives previews, contextual actions, and masking.
public enum ClipContentKind: String, Codable, Sendable, CaseIterable {
    case text
    case richText
    case url
    case email
    case phoneNumber
    case color
    case jwt
    case json
    case uuid
    case code
    case creditCard
    case image
    case fileReference
    case address
    case date
    case trackingNumber
    /// Detected secrets (API keys, private keys, probable passwords).
    /// Always masked in previews; short auto-expiry by default.
    case secret
}

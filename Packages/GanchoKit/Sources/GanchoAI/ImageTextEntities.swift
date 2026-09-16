import Foundation

/// Something a chip can act on in recognized text. Only web links and email
/// addresses qualify: they have one obvious, safe action. Phone numbers, dates
/// and codes stay plain text — copying the line already covers them.
public enum ImageTextEntity: Sendable, Hashable {
    /// An http(s) link; the host is what the chip shows.
    case link(URL)
    /// A mailto: address, kept both as text (to show) and as the URL to open.
    case email(address: String, url: URL)

    public var url: URL {
        switch self {
        case .link(let url): url
        case .email(_, let url): url
        }
    }
}

/// Finds actionable entities in OCR output. `NSDataDetector` does the matching,
/// the same detector `RuleClassifier` relies on, so a link INSIDE a sentence
/// counts and a bare classic domain ("www.example.com/docs") gets its scheme.
/// It is the ONLY way to build an `ImageTextEntity`, so whoever opens one
/// inherits this allowlist instead of repeating it.
public struct ImageTextEntityDetector: Sendable {
    /// Chips are a hint row, not a directory: three is the most the peek shows.
    public static let limit = 3

    public init() {}

    public func entities(in text: String) -> [ImageTextEntity] {
        guard
            let detector = try? NSDataDetector(
                types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return [] }
        var seen = Set<ImageTextEntity>()
        var found: [ImageTextEntity] = []
        for match in detector.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
            guard let url = match.url, let entity = Self.entity(for: url),
                seen.insert(entity).inserted
            else { continue }
            found.append(entity)
            if found.count == Self.limit { break }
        }
        return found
    }

    /// Only schemes a chip may open. OCR text is untrusted input: `file:`,
    /// `javascript:`, custom app schemes and the like never become a button.
    static func entity(for url: URL) -> ImageTextEntity? {
        switch url.scheme?.lowercased() {
        case "http", "https":
            return url.host == nil ? nil : .link(url)
        case "mailto":
            let raw = url.absoluteString.dropFirst("mailto:".count)
            let address = String(raw.split(separator: "?", maxSplits: 1).first ?? "")
            return address.contains("@") ? .email(address: address, url: url) : nil
        default:
            return nil
        }
    }
}

/// Whether recognized text deserves a Translate chip: it reads in a language
/// other than the interface language, and an engine can translate it NOW.
public enum ImageTextTranslation {
    /// The target to offer, or nil when translating would be pointless (same
    /// language, language unknown) or would fail (no installed pair and no
    /// model). The decision is `SmartPasteService.route`'s own, on the same
    /// sanitized text `translate` will send, so the chip never appears for a
    /// text the call would then refuse.
    public static func offer(
        for text: String, interface: Locale.Language, modelAvailable: Bool,
        engines: TranslationEngines = .live
    ) async -> Locale.Language? {
        guard
            let plan = await SmartPasteService().route(for: text, to: interface, engines: engines),
            plan.source.languageCode != interface.languageCode
        else { return nil }
        return plan.route == .native || modelAvailable ? interface : nil
    }
}

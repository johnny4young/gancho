import Foundation

/// A link clip's text as the URL a drop target or a share receives.
public enum LinkURL {
    /// One whole absolute URL with a host. A link captured without a scheme
    /// ("www.example.com") resolves the way the link detector that
    /// classified it reads it.
    public static func resolve(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        if let url = URL(string: trimmed), url.scheme != nil {
            return url.host() != nil ? url : nil
        }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard
            let detector = try? NSDataDetector(
                types: NSTextCheckingResult.CheckingType.link.rawValue),
            let match = detector.firstMatch(in: trimmed, range: range), match.range == range,
            let url = match.url, url.host() != nil
        else { return nil }
        return url
    }
}

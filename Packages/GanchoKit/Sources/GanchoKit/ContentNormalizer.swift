import Foundation

/// Canonicalizes clip content BEFORE hashing/storing, so cosmetic variance
/// never defeats dedupe (the Maccy 2.4 lesson: Google Sheets stamps a fresh
/// UUID into its rich payload on every copy; Safari appends tracking params
/// that change per session).
public enum ContentNormalizer {
    /// Query parameters that identify the CLICK, not the resource. Stripping
    /// them is also a privacy feature: trackers don't belong in history.
    static let trackingParameters: Set<String> = [
        "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
        "utm_id", "fbclid", "gclid", "dclid", "msclkid", "twclid", "yclid",
        "mc_cid", "mc_eid", "igshid", "igsh", "si", "_hsenc", "_hsmi",
        "vero_id", "wickedid", "oly_anon_id", "oly_enc_id", "ref_src"
    ]

    /// Strips tracking parameters from an absolute http(s) URL string.
    /// Non-URLs and relative strings come back untouched; remaining query
    /// order is preserved (the URL stays functionally identical).
    public static func normalizeURL(_ string: String) -> String {
        guard var components = URLComponents(string: string),
            let scheme = components.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            components.host != nil
        else { return string }

        guard let items = components.percentEncodedQueryItems, !items.isEmpty else {
            return string
        }
        let kept = items.filter {
            guard let name = $0.name.removingPercentEncoding else { return true }
            return !trackingParameters.contains(name.lowercased())
        }
        guard kept.count != items.count else { return string }
        // Decode names only for matching. Re-encoding values turns a literal
        // encoded plus into a form-space and changes functional parameters.
        components.percentEncodedQueryItems = kept.isEmpty ? nil : kept
        return components.string ?? string
    }

    /// Canonical text for hashing AND storage. URLs get tracking-stripped;
    /// other text passes through unchanged (content is never rewritten —
    /// only genuinely identifying noise is removed).
    public static func canonicalText(_ text: String, kind: ClipContentKind) -> String {
        switch kind {
        case .url:
            return normalizeURL(text.trimmingCharacters(in: .whitespacesAndNewlines))
        default:
            return text
        }
    }
}

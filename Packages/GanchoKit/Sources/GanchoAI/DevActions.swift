import Foundation
import GanchoKit

/// Developer actions pack: pure, offline, zero-network transforms over clip
/// text. The right actions surface automatically from the detected kind;
/// every action is also exposable as an App Intent (same functions, no
/// logic forks). Free tier on purpose — this is the word-of-mouth spear.
public enum DevActions {
    public enum ActionID: String, Sendable, CaseIterable {
        case decodeJWT
        case jsonPretty
        case jsonMinify
        case base64Encode
        case base64Decode
        case parseURL
        case convertColor
        case uuidFormats
    }

    public struct Action: Identifiable, Sendable {
        public let id: ActionID
        /// English title; UI localizes via the String Catalog key.
        public let title: String
        public let transform: @Sendable (String) throws -> String
    }

    public enum ActionError: Error, Equatable {
        case notApplicable(String)
    }

    /// The actions that make sense for a clip kind, in display order.
    public static func actions(for kind: ClipContentKind) -> [Action] {
        switch kind {
        case .jwt:
            [action(.decodeJWT)]
        case .json:
            [action(.jsonPretty), action(.jsonMinify), action(.base64Encode)]
        case .url:
            [action(.parseURL), action(.base64Encode)]
        case .color:
            [action(.convertColor)]
        case .uuid:
            [action(.uuidFormats)]
        case .text, .code:
            [action(.base64Encode), action(.base64Decode)]
        default:
            []
        }
    }

    public static func action(_ id: ActionID) -> Action {
        switch id {
        case .decodeJWT:
            Action(id: id, title: "Decode JWT", transform: decodeJWT)
        case .jsonPretty:
            Action(id: id, title: "Pretty-print JSON", transform: jsonPretty)
        case .jsonMinify:
            Action(id: id, title: "Minify JSON", transform: jsonMinify)
        case .base64Encode:
            Action(id: id, title: "Base64 encode", transform: base64Encode)
        case .base64Decode:
            Action(id: id, title: "Base64 decode", transform: base64Decode)
        case .parseURL:
            Action(id: id, title: "Parse URL", transform: parseURL)
        case .convertColor:
            Action(id: id, title: "Convert color", transform: convertColor)
        case .uuidFormats:
            Action(id: id, title: "UUID formats", transform: uuidFormats)
        }
    }

    /// Runs one action by id — the single entry point App Intents share
    /// with the UI.
    public static func run(_ id: ActionID, on text: String) throws -> String {
        try action(id).transform(text)
    }

    // MARK: - Transforms

    static func decodeJWT(_ text: String) throws -> String {
        let segments = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ".")
        guard segments.count == 3,
            let header = decodeBase64URLJSON(String(segments[0])),
            let claims = decodeBase64URLJSON(String(segments[1]))
        else { throw ActionError.notApplicable("not a decodable JWT") }

        var output = "HEADER\n\(header)\n\nCLAIMS\n\(claims)"
        if let object = jsonObject(claims) as? [String: Any],
            let exp = object["exp"] as? TimeInterval
        {
            let date = Date(timeIntervalSince1970: exp)
            let formatter = ISO8601DateFormatter()
            let expired = date < .now ? " — EXPIRED" : ""
            output += "\n\nexp: \(formatter.string(from: date))\(expired)"
        }
        return output
    }

    static func jsonPretty(_ text: String) throws -> String {
        guard let object = jsonObject(text),
            let data = try? JSONSerialization.data(
                withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
            let pretty = String(data: data, encoding: .utf8)
        else { throw ActionError.notApplicable("not valid JSON") }
        return pretty
    }

    static func jsonMinify(_ text: String) throws -> String {
        guard let object = jsonObject(text),
            let data = try? JSONSerialization.data(
                withJSONObject: object, options: [.sortedKeys]),
            let minified = String(data: data, encoding: .utf8)
        else { throw ActionError.notApplicable("not valid JSON") }
        return minified
    }

    static func base64Encode(_ text: String) throws -> String {
        Data(text.utf8).base64EncodedString()
    }

    static func base64Decode(_ text: String) throws -> String {
        guard
            let data = Data(base64Encoded: text.trimmingCharacters(in: .whitespacesAndNewlines)),
            let decoded = String(data: data, encoding: .utf8)
        else { throw ActionError.notApplicable("not base64 text") }
        return decoded
    }

    static func parseURL(_ text: String) throws -> String {
        guard
            let components = URLComponents(
                string: text.trimmingCharacters(in: .whitespacesAndNewlines)),
            components.scheme != nil
        else { throw ActionError.notApplicable("not a URL") }
        var lines: [String] = []
        lines.append("scheme: \(components.scheme ?? "")")
        if let host = components.host { lines.append("host: \(host)") }
        if let port = components.port { lines.append("port: \(port)") }
        if !components.path.isEmpty { lines.append("path: \(components.path)") }
        if let items = components.queryItems, !items.isEmpty {
            lines.append("query:")
            for item in items {
                lines.append("  \(item.name) = \(item.value ?? "")")
            }
        }
        if let fragment = components.fragment { lines.append("fragment: \(fragment)") }
        return lines.joined(separator: "\n")
    }

    static func convertColor(_ text: String) throws -> String {
        guard let rgb = parseColor(text) else {
            throw ActionError.notApplicable("not a parseable color")
        }
        let (r, g, b) = rgb
        let (h, s, l) = rgbToHSL(r: r, g: g, b: b)
        return """
            hex: #\(String(format: "%02X%02X%02X", r, g, b))
            rgb: rgb(\(r), \(g), \(b))
            hsl: hsl(\(h), \(s)%, \(l)%)
            """
    }

    static func uuidFormats(_ text: String) throws -> String {
        guard let uuid = UUID(uuidString: text.trimmingCharacters(in: .whitespacesAndNewlines))
        else { throw ActionError.notApplicable("not a UUID") }
        let canonical = uuid.uuidString
        return """
            upper: \(canonical)
            lower: \(canonical.lowercased())
            compact: \(canonical.replacingOccurrences(of: "-", with: "").lowercased())
            """
    }

    // MARK: - Helpers

    private static func jsonObject(_ text: String) -> Any? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private static func decodeBase64URLJSON(_ segment: String) -> String? {
        var base64 =
            segment
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while base64.count % 4 != 0 { base64.append("=") }
        guard let data = Data(base64Encoded: base64),
            let object = try? JSONSerialization.jsonObject(with: data),
            let pretty = try? JSONSerialization.data(
                withJSONObject: object, options: [.prettyPrinted, .sortedKeys])
        else { return nil }
        return String(data: pretty, encoding: .utf8)
    }

    /// Accepts #hex (3/6/8), rgb()/rgba(), hsl()/hsla().
    private static func parseColor(_ text: String) -> (Int, Int, Int)? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        if trimmed.hasPrefix("#") {
            var hex = String(trimmed.dropFirst())
            if hex.count == 3 { hex = hex.map { "\($0)\($0)" }.joined() }
            if hex.count == 8 { hex = String(hex.dropFirst(2)) }
            guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
            return (Int((value >> 16) & 0xFF), Int((value >> 8) & 0xFF), Int(value & 0xFF))
        }
        guard let open = trimmed.firstIndex(of: "("), trimmed.hasSuffix(")") else { return nil }
        let function = String(trimmed[..<open])
        let body = trimmed[trimmed.index(after: open)..<trimmed.index(before: trimmed.endIndex)]
        let parts = body.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: "")
        }
        guard parts.count >= 3 else { return nil }
        switch function {
        case "rgb", "rgba":
            guard let r = Int(parts[0]), let g = Int(parts[1]), let b = Int(parts[2]),
                (0...255).contains(r), (0...255).contains(g), (0...255).contains(b)
            else { return nil }
            return (r, g, b)
        case "hsl", "hsla":
            guard let h = Double(parts[0]), let s = Double(parts[1]), let l = Double(parts[2])
            else { return nil }
            return hslToRGB(h: h, s: s / 100, l: l / 100)
        default:
            return nil
        }
    }

    private static func hslToRGB(h: Double, s: Double, l: Double) -> (Int, Int, Int) {
        let c = (1 - abs(2 * l - 1)) * s
        let hPrime = h.truncatingRemainder(dividingBy: 360) / 60
        let x = c * (1 - abs(hPrime.truncatingRemainder(dividingBy: 2) - 1))
        let (r1, g1, b1): (Double, Double, Double) =
            switch Int(hPrime) {
            case 0: (c, x, 0)
            case 1: (x, c, 0)
            case 2: (0, c, x)
            case 3: (0, x, c)
            case 4: (x, 0, c)
            default: (c, 0, x)
            }
        let m = l - c / 2
        return (
            Int(((r1 + m) * 255).rounded()),
            Int(((g1 + m) * 255).rounded()),
            Int(((b1 + m) * 255).rounded())
        )
    }

    private static func rgbToHSL(r: Int, g: Int, b: Int) -> (Int, Int, Int) {
        let rd = Double(r) / 255
        let gd = Double(g) / 255
        let bd = Double(b) / 255
        let maxValue = max(rd, gd, bd)
        let minValue = min(rd, gd, bd)
        let delta = maxValue - minValue
        let l = (maxValue + minValue) / 2
        guard delta > 0 else { return (0, 0, Int((l * 100).rounded())) }
        let s = delta / (1 - abs(2 * l - 1))
        var h: Double =
            switch maxValue {
            case rd: ((gd - bd) / delta).truncatingRemainder(dividingBy: 6)
            case gd: (bd - rd) / delta + 2
            default: (rd - gd) / delta + 4
            }
        h *= 60
        if h < 0 { h += 360 }
        return (Int(h.rounded()), Int((s * 100).rounded()), Int((l * 100).rounded()))
    }
}

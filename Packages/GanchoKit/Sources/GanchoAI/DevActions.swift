import CryptoKit
import Foundation
import GanchoKit

// DevActions is a compact registry plus pure transforms; splitting it would add
// indirection without improving this SwiftLint adoption.
// swiftlint:disable type_body_length

/// Developer actions pack: pure, offline, zero-network transforms over clip
/// text. The right actions surface automatically from the detected kind;
/// every action is also exposable as an App Intent (same functions, no
/// logic forks). Free tier on purpose — this is the word-of-mouth spear.
public enum DevActions {
    // swiftlint:enable type_body_length
    public enum ActionID: String, Sendable, CaseIterable {
        case decodeJWT
        case jsonPretty
        case jsonMinify
        case base64Encode
        case base64Decode
        case parseURL
        case convertColor
        case uuidFormats
        case sha256Hex
        case sha1Hex
        case md5Hex
        case urlEncode
        case urlDecode
        case caseConvert
        case epochToDate
        case dateToEpoch
        case sortLines
        case dedupeLines
        case reverseLines
        case countStats
        case htmlEntityEncode
        case htmlEntityDecode
        case slugify
        case numberBaseConvert
        case jsonEscape
        case jsonUnescape
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
            [
                action(.jsonPretty), action(.jsonMinify), action(.jsonEscape),
                action(.base64Encode)
            ]
        case .url:
            [
                action(.parseURL), action(.urlEncode), action(.urlDecode),
                action(.base64Encode)
            ]
        case .color:
            [action(.convertColor)]
        case .uuid:
            [action(.uuidFormats)]
        case .date:
            [action(.dateToEpoch)]
        case .text:
            [
                action(.caseConvert), action(.slugify), action(.countStats),
                action(.sortLines), action(.dedupeLines), action(.reverseLines),
                action(.epochToDate), action(.numberBaseConvert),
                action(.urlEncode), action(.htmlEntityEncode),
                action(.base64Encode), action(.base64Decode), action(.sha256Hex)
            ]
        case .code:
            [
                action(.jsonEscape), action(.jsonUnescape),
                action(.htmlEntityEncode), action(.htmlEntityDecode),
                action(.urlEncode), action(.urlDecode),
                action(.caseConvert), action(.countStats),
                action(.sortLines), action(.dedupeLines),
                action(.base64Encode), action(.base64Decode),
                action(.sha256Hex), action(.sha1Hex), action(.md5Hex)
            ]
        default:
            []
        }
    }

    // The registry is one switch by design so App Intents and UI lists cannot
    // drift from the transform definitions.
    // swiftlint:disable:next cyclomatic_complexity
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
        case .sha256Hex:
            Action(id: id, title: "SHA-256 hash", transform: sha256Hex)
        case .sha1Hex:
            Action(id: id, title: "SHA-1 hash", transform: sha1Hex)
        case .md5Hex:
            Action(id: id, title: "MD5 hash", transform: md5Hex)
        case .urlEncode:
            Action(id: id, title: "URL encode", transform: urlEncode)
        case .urlDecode:
            Action(id: id, title: "URL decode", transform: urlDecode)
        case .caseConvert:
            Action(id: id, title: "Convert case", transform: caseConvert)
        case .epochToDate:
            Action(id: id, title: "Epoch to date", transform: epochToDate)
        case .dateToEpoch:
            Action(id: id, title: "Date to epoch", transform: dateToEpoch)
        case .sortLines:
            Action(id: id, title: "Sort lines", transform: sortLines)
        case .dedupeLines:
            Action(id: id, title: "Dedupe lines", transform: dedupeLines)
        case .reverseLines:
            Action(id: id, title: "Reverse lines", transform: reverseLines)
        case .countStats:
            Action(id: id, title: "Count stats", transform: countStats)
        case .htmlEntityEncode:
            Action(id: id, title: "HTML-entity encode", transform: htmlEntityEncode)
        case .htmlEntityDecode:
            Action(id: id, title: "HTML-entity decode", transform: htmlEntityDecode)
        case .slugify:
            Action(id: id, title: "Slugify", transform: slugify)
        case .numberBaseConvert:
            Action(id: id, title: "Convert number base", transform: numberBaseConvert)
        case .jsonEscape:
            Action(id: id, title: "JSON-escape string", transform: jsonEscape)
        case .jsonUnescape:
            Action(id: id, title: "JSON-unescape string", transform: jsonUnescape)
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
        let (red, green, blue) = rgb
        let (hue, saturation, lightness) = rgbToHSL(red: red, green: green, blue: blue)
        return """
            hex: #\(String(format: "%02X%02X%02X", red, green, blue))
            rgb: rgb(\(red), \(green), \(blue))
            hsl: hsl(\(hue), \(saturation)%, \(lightness)%)
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

    static func sha256Hex(_ text: String) throws -> String {
        SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func sha1Hex(_ text: String) throws -> String {
        Insecure.SHA1.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func md5Hex(_ text: String) throws -> String {
        Insecure.MD5.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func urlEncode(_ text: String) throws -> String {
        // RFC 3986 unreserved characters only — everything else gets escaped.
        let unreserved = CharacterSet(
            charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
                + "abcdefghijklmnopqrstuvwxyz0123456789-._~")
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: unreserved)
        else { throw ActionError.notApplicable("could not percent-encode") }
        return encoded
    }

    static func urlDecode(_ text: String) throws -> String {
        guard let decoded = text.removingPercentEncoding
        else { throw ActionError.notApplicable("not valid percent-encoding") }
        return decoded
    }

    static func caseConvert(_ text: String) throws -> String {
        let words = splitWords(text)
        guard !words.isEmpty else { throw ActionError.notApplicable("no words to convert") }
        let lower = words.map { $0.lowercased() }
        let capitalized = lower.map { $0.prefix(1).uppercased() + String($0.dropFirst()) }
        let camel = ([lower[0]] + capitalized.dropFirst()).joined()
        return """
            camel: \(camel)
            snake: \(lower.joined(separator: "_"))
            kebab: \(lower.joined(separator: "-"))
            title: \(capitalized.joined(separator: " "))
            upper: \(words.joined(separator: " ").uppercased())
            lower: \(lower.joined(separator: " "))
            """
    }

    static func epochToDate(_ text: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let raw = Int64(trimmed), raw > 0 else {
            throw ActionError.notApplicable("not a Unix timestamp")
        }
        // 12+ digit values are read as milliseconds, shorter ones as seconds.
        let seconds = raw >= 100_000_000_000 ? Double(raw) / 1000 : Double(raw)
        guard seconds < 253_402_300_800 else {  // before year 10000
            throw ActionError.notApplicable("not a plausible Unix timestamp")
        }
        let date = Date(timeIntervalSince1970: seconds)
        let utc = ISO8601DateFormatter()
        let local = ISO8601DateFormatter()
        local.timeZone = .current
        return """
            utc: \(utc.string(from: date))
            local: \(local.string(from: date))
            """
    }

    static func dateToEpoch(_ text: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = plain.date(from: trimmed) ?? fractional.date(from: trimmed)
        else { throw ActionError.notApplicable("not an ISO-8601 date") }
        let millis = Int64((date.timeIntervalSince1970 * 1000).rounded())
        return """
            seconds: \(millis / 1000)
            milliseconds: \(millis)
            """
    }

    static func sortLines(_ text: String) throws -> String {
        try splitLines(text).sorted().joined(separator: "\n")
    }

    /// Stable: keeps the first occurrence of each line, in original order.
    static func dedupeLines(_ text: String) throws -> String {
        var seen = Set<String>()
        return try splitLines(text).filter { seen.insert($0).inserted }
            .joined(separator: "\n")
    }

    static func reverseLines(_ text: String) throws -> String {
        try splitLines(text).reversed().joined(separator: "\n")
    }

    static func countStats(_ text: String) throws -> String {
        let lineCount = text.isEmpty ? 0 : text.components(separatedBy: "\n").count
        let wordCount = text.split(whereSeparator: { $0.isWhitespace }).count
        return """
            lines: \(lineCount)
            words: \(wordCount)
            characters: \(text.count)
            bytes: \(text.utf8.count)
            """
    }

    static func htmlEntityEncode(_ text: String) throws -> String {
        var output = ""
        for char in text {
            switch char {
            case "&": output += "&amp;"
            case "<": output += "&lt;"
            case ">": output += "&gt;"
            case "\"": output += "&quot;"
            case "'": output += "&#39;"
            default: output.append(char)
            }
        }
        return output
    }

    static func htmlEntityDecode(_ text: String) throws -> String {
        var output = ""
        var index = text.startIndex
        while index < text.endIndex {
            let char = text[index]
            let windowEnd =
                text.index(index, offsetBy: 12, limitedBy: text.endIndex) ?? text.endIndex
            guard char == "&",
                let semicolon = text[index..<windowEnd].firstIndex(of: ";")
            else {
                output.append(char)
                index = text.index(after: index)
                continue
            }
            let body = String(text[text.index(after: index)..<semicolon])
            if let decoded = decodeEntity(body) {
                output.append(decoded)
                index = text.index(after: semicolon)
            } else {
                // Not an entity we know — keep the ampersand literal.
                output.append(char)
                index = text.index(after: index)
            }
        }
        return output
    }

    static func slugify(_ text: String) throws -> String {
        let folded = text.folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX"))
        var slug = ""
        var pendingHyphen = false
        for char in folded.lowercased() {
            if char.isASCII, char.isLetter || char.isNumber {
                if pendingHyphen, !slug.isEmpty { slug.append("-") }
                pendingHyphen = false
                slug.append(char)
            } else {
                pendingHyphen = true
            }
        }
        guard !slug.isEmpty else { throw ActionError.notApplicable("no letters or digits") }
        return slug
    }

    static func numberBaseConvert(_ text: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var body = trimmed[...]
        let negative = body.hasPrefix("-")
        if negative { body = body.dropFirst() }
        let parsed: UInt64? =
            if body.hasPrefix("0x") {
                UInt64(body.dropFirst(2), radix: 16)
            } else if body.hasPrefix("0b") {
                UInt64(body.dropFirst(2), radix: 2)
            } else if body.hasPrefix("0o") {
                UInt64(body.dropFirst(2), radix: 8)
            } else {
                UInt64(body, radix: 10)
            }
        guard let value = parsed else { throw ActionError.notApplicable("not an integer") }
        let sign = negative ? "-" : ""
        return """
            dec: \(sign)\(value)
            hex: \(sign)0x\(String(value, radix: 16))
            bin: \(sign)0b\(String(value, radix: 2))
            oct: \(sign)0o\(String(value, radix: 8))
            """
    }

    static func jsonEscape(_ text: String) throws -> String {
        // Serialize as a one-element array, then strip the brackets — gives
        // the bare string literal without hand-rolled escaping rules.
        guard let data = try? JSONSerialization.data(withJSONObject: [text]),
            let wrapped = String(data: data, encoding: .utf8),
            wrapped.count >= 2
        else { throw ActionError.notApplicable("could not JSON-escape") }
        return String(wrapped.dropFirst().dropLast())
    }

    static func jsonUnescape(_ text: String) throws -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let data = Data("[\(trimmed)]".utf8)
        guard trimmed.count >= 2, trimmed.hasPrefix("\""), trimmed.hasSuffix("\""),
            let strings = (try? JSONSerialization.jsonObject(with: data)) as? [String],
            strings.count == 1
        else { throw ActionError.notApplicable("not a JSON string literal") }
        return strings[0]
    }

    // MARK: - Helpers

    /// Splits into words on non-alphanumerics and lower→upper camel humps.
    private static func splitWords(_ text: String) -> [String] {
        var words: [String] = []
        var current = ""
        var previous: Character?
        for char in text {
            guard char.isLetter || char.isNumber else {
                if !current.isEmpty { words.append(current) }
                current = ""
                previous = nil
                continue
            }
            if let previous, previous.isLowercase || previous.isNumber, char.isUppercase,
                !current.isEmpty
            {
                words.append(current)
                current = ""
            }
            current.append(char)
            previous = char
        }
        if !current.isEmpty { words.append(current) }
        return words
    }

    private static func splitLines(_ text: String) throws -> [String] {
        let lines = text.components(separatedBy: "\n")
        guard lines.count > 1 else {
            throw ActionError.notApplicable("needs more than one line")
        }
        return lines
    }

    /// `body` is the text between `&` and `;` — named or numeric entity.
    private static func decodeEntity(_ body: String) -> Character? {
        let named: [String: Character] = [
            "amp": "&", "lt": "<", "gt": ">", "quot": "\"", "apos": "'", "nbsp": "\u{00A0}"
        ]
        if body.hasPrefix("#x") || body.hasPrefix("#X") {
            guard let value = UInt32(body.dropFirst(2), radix: 16),
                let scalar = Unicode.Scalar(value)
            else { return nil }
            return Character(scalar)
        }
        if body.hasPrefix("#") {
            guard let value = UInt32(body.dropFirst(), radix: 10),
                let scalar = Unicode.Scalar(value)
            else { return nil }
            return Character(scalar)
        }
        return named[body]
    }

    private static func jsonObject(_ text: String) -> Any? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data)
    }

    private static func decodeBase64URLJSON(_ segment: String) -> String? {
        var base64 =
            segment
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while !base64.count.isMultiple(of: 4) { base64.append("=") }
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
            guard
                let red = Int(parts[0]),
                let green = Int(parts[1]),
                let blue = Int(parts[2]),
                (0...255).contains(red),
                (0...255).contains(green),
                (0...255).contains(blue)
            else { return nil }
            return (red, green, blue)
        case "hsl", "hsla":
            guard
                let hue = Double(parts[0]),
                let saturation = Double(parts[1]),
                let lightness = Double(parts[2])
            else { return nil }
            return hslToRGB(hue: hue, saturation: saturation / 100, lightness: lightness / 100)
        default:
            return nil
        }
    }

    private static func hslToRGB(
        hue: Double, saturation: Double, lightness: Double
    ) -> (Int, Int, Int) {
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let huePrime = hue.truncatingRemainder(dividingBy: 360) / 60
        let secondary = chroma * (1 - abs(huePrime.truncatingRemainder(dividingBy: 2) - 1))
        let (redComponent, greenComponent, blueComponent): (Double, Double, Double) =
            switch Int(huePrime) {
            case 0: (chroma, secondary, 0)
            case 1: (secondary, chroma, 0)
            case 2: (0, chroma, secondary)
            case 3: (0, secondary, chroma)
            case 4: (secondary, 0, chroma)
            default: (chroma, 0, secondary)
            }
        let match = lightness - chroma / 2
        return (
            Int(((redComponent + match) * 255).rounded()),
            Int(((greenComponent + match) * 255).rounded()),
            Int(((blueComponent + match) * 255).rounded())
        )
    }

    private static func rgbToHSL(red: Int, green: Int, blue: Int) -> (Int, Int, Int) {
        let redDecimal = Double(red) / 255
        let greenDecimal = Double(green) / 255
        let blueDecimal = Double(blue) / 255
        let maxValue = max(redDecimal, greenDecimal, blueDecimal)
        let minValue = min(redDecimal, greenDecimal, blueDecimal)
        let delta = maxValue - minValue
        let lightness = (maxValue + minValue) / 2
        guard delta > 0 else { return (0, 0, Int((lightness * 100).rounded())) }
        let saturation = delta / (1 - abs(2 * lightness - 1))
        var hue: Double =
            switch maxValue {
            case redDecimal:
                ((greenDecimal - blueDecimal) / delta).truncatingRemainder(dividingBy: 6)
            case greenDecimal: (blueDecimal - redDecimal) / delta + 2
            default: (redDecimal - greenDecimal) / delta + 4
            }
        hue *= 60
        if hue < 0 { hue += 360 }
        return (
            Int(hue.rounded()), Int((saturation * 100).rounded()), Int((lightness * 100).rounded())
        )
    }
}

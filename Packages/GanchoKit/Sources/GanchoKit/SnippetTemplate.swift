import Foundation

/// {placeholder} templates for snippets: parse the fields, fill them, paste
/// the result. Supports defaults (`{name:World}`) and repeated fields
/// (filled once, applied everywhere).
public enum SnippetTemplate {
    public struct Field: Sendable, Equatable, Identifiable {
        public var id: String { name }
        public let name: String
        public let defaultValue: String?
    }

    /// Fields in first-appearance order, deduplicated by name.
    public static func fields(in template: String) -> [Field] {
        var seen = Set<String>()
        var fields: [Field] = []
        let pattern = #"\{([A-Za-z0-9_ ]+?)(?::([^{}]*))?\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let matches = regex.matches(
            in: template, range: NSRange(template.startIndex..., in: template))
        for match in matches {
            guard let nameRange = Range(match.range(at: 1), in: template) else { continue }
            let name = String(template[nameRange]).trimmingCharacters(in: .whitespaces)
            guard !name.isEmpty, seen.insert(name).inserted else { continue }
            let defaultValue = Range(match.range(at: 2), in: template)
                .map { String(template[$0]) }
            fields.append(Field(name: name, defaultValue: defaultValue))
        }
        return fields
    }

    /// Fills every occurrence; missing values fall back to the field default,
    /// then to the empty string (never leave braces in pasted output).
    public static func fill(_ template: String, values: [String: String]) -> String {
        let pattern = #"\{([A-Za-z0-9_ ]+?)(?::([^{}]*))?\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return template }
        var result = ""
        var cursor = template.startIndex
        for match in regex.matches(
            in: template, range: NSRange(template.startIndex..., in: template))
        {
            guard let full = Range(match.range, in: template),
                let nameRange = Range(match.range(at: 1), in: template)
            else { continue }
            result += template[cursor..<full.lowerBound]
            let name = String(template[nameRange]).trimmingCharacters(in: .whitespaces)
            let fallback =
                Range(match.range(at: 2), in: template)
                .map { String(template[$0]) } ?? ""
            result += values[name] ?? fallback
            cursor = full.upperBound
        }
        result += template[cursor...]
        return result
    }

    public static func isTemplate(_ text: String) -> Bool {
        !fields(in: text).isEmpty
    }
}

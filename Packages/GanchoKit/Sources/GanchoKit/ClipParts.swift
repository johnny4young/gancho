import Foundation

/// Where a merged clip's parts begin and end: the separator between them and
/// each part's length in characters. Text edited after the merge no longer
/// matches, and `split` then answers nil.
public struct ClipParts: Codable, Sendable, Equatable {
    public enum Separator: String, Codable, Sendable, CaseIterable {
        case newline, space, comma

        public var text: String {
            switch self {
            case .newline: "\n"
            case .space: " "
            case .comma: ", "
            }
        }
    }

    public static let maximumParts = 20

    public var separator: Separator
    public var lengths: [Int]

    public init(separator: Separator, lengths: [Int]) {
        self.separator = separator
        self.lengths = lengths
    }

    /// Joins parts with a separator; nil for fewer than two or more than the cap.
    public static func join(_ parts: [String], separator: Separator) -> (String, ClipParts)? {
        guard (2...maximumParts).contains(parts.count) else { return nil }
        return (
            parts.joined(separator: separator.text),
            ClipParts(separator: separator, lengths: parts.map(\.count))
        )
    }

    /// The parts of `text`, or nil when it no longer matches these boundaries.
    public func split(_ text: String) -> [String]? {
        guard (2...Self.maximumParts).contains(lengths.count), lengths.allSatisfy({ $0 >= 0 })
        else { return nil }
        var parts: [String] = []
        var rest = Substring(text)
        for (index, length) in lengths.enumerated() {
            guard rest.count >= length else { return nil }
            parts.append(String(rest.prefix(length)))
            rest = rest.dropFirst(length)
            if index < lengths.count - 1 {
                guard rest.hasPrefix(separator.text) else { return nil }
                rest = rest.dropFirst(separator.text.count)
            }
        }
        return rest.isEmpty ? parts : nil
    }

    /// The same parts under another separator.
    public func rejoined(_ text: String, with separator: Separator) -> (String, ClipParts)? {
        split(text).flatMap { Self.join($0, separator: separator) }
    }

    /// The stored and synced form, small JSON.
    public var encoded: String? {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) }
    }

    public init?(encoded: String?) {
        guard let encoded, encoded.utf8.count <= 1_024,
            let decoded = try? JSONDecoder().decode(ClipParts.self, from: Data(encoded.utf8)),
            (2...Self.maximumParts).contains(decoded.lengths.count)
        else { return nil }
        self = decoded
    }
}

import Foundation
import GanchoAI

/// A word-level diff for "Describe the change": what the model kept, removed
/// and added. Whitespace stays attached to its word, so joining every
/// segment of one side rebuilds that side exactly. Pure, no model.
public enum WordDiff {
    public enum Kind: Equatable, Sendable { case same, removed, added }

    public struct Segment: Equatable, Sendable {
        public let kind: Kind
        public let text: String
    }

    /// Longer texts compare line by line, which keeps the table small.
    static let maximumTokens = 2_000

    public static func diff(_ old: String, _ new: String) -> [Segment] {
        let before = tokens(old)
        let after = tokens(new)
        guard before.count <= maximumTokens, after.count <= maximumTokens else {
            return [Segment(kind: .removed, text: old), Segment(kind: .added, text: new)]
        }
        // Longest common subsequence over the tokens.
        var table = Array(
            repeating: Array(repeating: 0, count: after.count + 1), count: before.count + 1)
        for i in stride(from: before.count - 1, through: 0, by: -1) {
            for j in stride(from: after.count - 1, through: 0, by: -1) {
                table[i][j] =
                    before[i] == after[j]
                    ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }
        var segments: [Segment] = []
        var i = 0
        var j = 0
        while i < before.count || j < after.count {
            if i < before.count, j < after.count, before[i] == after[j] {
                append(.same, before[i], to: &segments)
                i += 1
                j += 1
            } else if j < after.count, i == before.count || table[i][j + 1] >= table[i + 1][j] {
                append(.added, after[j], to: &segments)
                j += 1
            } else {
                append(.removed, before[i], to: &segments)
                i += 1
            }
        }
        return segments
    }

    /// Words with their trailing whitespace.
    static func tokens(_ text: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inSpace = false
        for character in text {
            if character.isWhitespace {
                inSpace = true
            } else if inSpace {
                result.append(current)
                current = ""
                inSpace = false
            }
            current.append(character)
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private static func append(_ kind: Kind, _ text: String, to segments: inout [Segment]) {
        if let last = segments.last, last.kind == kind {
            segments[segments.count - 1] = Segment(kind: kind, text: last.text + text)
        } else {
            segments.append(Segment(kind: kind, text: text))
        }
    }
}

/// The change requests a user kept: local preferences, never synced, newest
/// first, without duplicates.
public struct SavedPrompts: Equatable, Sendable {
    public static let defaultsKey = "saved-change-prompts"
    public static let maximumCount = 12
    /// Matches the longest request the model receives.
    public static let maximumLength = SmartPasteService.maxChangeCharacters

    public private(set) var prompts: [String]

    public init(prompts: [String] = []) {
        self.prompts = Array(prompts.prefix(Self.maximumCount))
    }

    public static func load(from defaults: UserDefaults) -> SavedPrompts {
        SavedPrompts(prompts: defaults.stringArray(forKey: defaultsKey) ?? [])
    }

    public func save(to defaults: UserDefaults) {
        defaults.set(prompts, forKey: Self.defaultsKey)
    }

    /// Keeps a request only when it is what ran: within the length limit and
    /// free of anything the sanitizer would redact.
    @discardableResult
    public mutating func add(_ prompt: String) -> Bool {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count <= Self.maximumLength,
            ModelInputSanitizer.sanitized(trimmed) == trimmed
        else { return false }
        prompts.removeAll { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
        prompts.insert(trimmed, at: 0)
        prompts = Array(prompts.prefix(Self.maximumCount))
        return true
    }

    public mutating func remove(_ prompt: String) {
        prompts.removeAll { $0 == prompt }
    }
}

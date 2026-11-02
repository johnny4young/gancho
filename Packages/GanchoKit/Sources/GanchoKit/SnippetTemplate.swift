import Foundation

/// {placeholder} templates for snippets: parse them, fill them, paste the
/// result. Fields ask for a value, with an optional default (`{name:World}`),
/// and repeat as one. `{clipboard}`, `{clipboard offset=1}`, `{date}`,
/// `{date +2d}` and `{cursor}` fill themselves, and `| trim` or `| uppercase`
/// can follow any of them but the cursor. Anything else stays literal.
public enum SnippetTemplate {
    public struct Field: Sendable, Equatable, Identifiable {
        public var id: String { name }
        public let name: String
        public let defaultValue: String?
    }

    public enum Placeholder: Sendable, Equatable {
        case field(name: String, defaultValue: String?)
        /// 0 is the clipboard now; 1 and up count back through history.
        case clipboard(offset: Int)
        /// Days from today.
        case date(dayOffset: Int)
        case cursor
    }

    public enum Modifier: String, Sendable, CaseIterable {
        case trim, uppercase

        func apply(to text: String) -> String {
            switch self {
            case .trim: text.trimmingCharacters(in: .whitespacesAndNewlines)
            case .uppercase: text.uppercased()
            }
        }
    }

    public struct Token: Sendable, Equatable {
        public let range: Range<String.Index>
        public let placeholder: Placeholder
        public let modifiers: [Modifier]
    }

    public struct Rendered: Sendable, Equatable {
        public let text: String
        /// Characters between the first `{cursor}` and the end; nil without one.
        public let charactersAfterCursor: Int?
    }

    /// Every placeholder, in order.
    public static func tokens(in template: String) -> [Token] {
        guard let regex = try? NSRegularExpression(pattern: #"\{([^{}]*)\}"#) else { return [] }
        return regex.matches(in: template, range: NSRange(template.startIndex..., in: template))
            .compactMap { match in
                guard let full = Range(match.range, in: template),
                    let inner = Range(match.range(at: 1), in: template),
                    let parsed = parse(template[inner])
                else { return nil }
                return Token(range: full, placeholder: parsed.0, modifiers: parsed.1)
            }
    }

    private static func parse(_ inner: Substring) -> (Placeholder, [Modifier])? {
        var rest = inner
        var modifiers: [Modifier] = []
        // Only known modifiers count, so an old `{name:a|b}` keeps its default.
        while let bar = rest.lastIndex(of: "|"),
            let modifier = Modifier(
                rawValue: rest[rest.index(after: bar)...]
                    .trimmingCharacters(in: .whitespacesAndNewlines))
        {
            modifiers.insert(modifier, at: 0)
            rest = rest[..<bar]
            // The space before the bar separates; it isn't part of a default.
            while rest.last?.isWhitespace == true { rest = rest.dropLast() }
        }
        let head = rest.trimmingCharacters(in: .whitespaces)
        if head == "cursor" { return modifiers.isEmpty ? (.cursor, []) : nil }
        if let placeholder = selfFilling(head) { return (placeholder, modifiers) }
        return field(rest).map { ($0, modifiers) }
    }

    private static func selfFilling(_ head: String) -> Placeholder? {
        if head == "clipboard" { return .clipboard(offset: 0) }
        if head == "date" { return .date(dayOffset: 0) }
        if head.hasPrefix("clipboard offset="),
            let offset = number(head.dropFirst("clipboard offset=".count), maxDigits: 3)
        {
            return .clipboard(offset: offset)
        }
        guard head.hasPrefix("date "), head.hasSuffix("d") else { return nil }
        let amount = head.dropFirst("date ".count).dropLast()
        guard let sign = amount.first, sign == "+" || sign == "-",
            let days = number(amount.dropFirst(), maxDigits: 4)
        else { return nil }
        return .date(dayOffset: sign == "+" ? days : -days)
    }

    private static func number(_ digits: Substring, maxDigits: Int) -> Int? {
        guard !digits.isEmpty, digits.count <= maxDigits,
            digits.allSatisfy({ $0.isASCII && $0.isNumber })
        else { return nil }
        return Int(digits)
    }

    private static func field(_ text: Substring) -> Placeholder? {
        let colon = text.firstIndex(of: ":")
        let rawName = colon.map { text[..<$0] } ?? text
        guard !rawName.isEmpty,
            rawName.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "_ ".contains($0)) })
        else { return nil }
        return .field(
            name: rawName.trimmingCharacters(in: .whitespaces),
            defaultValue: colon.map { String(text[text.index(after: $0)...]) })
    }

    /// Fields in first-appearance order, deduplicated by name.
    public static func fields(in template: String) -> [Field] {
        var seen = Set<String>()
        return tokens(in: template).compactMap { token in
            guard case .field(let name, let defaultValue) = token.placeholder, !name.isEmpty,
                seen.insert(name).inserted
            else { return nil }
            return Field(name: name, defaultValue: defaultValue)
        }
    }

    /// The day offsets of its date placeholders, each once, in order.
    public static func dateOffsets(in template: String) -> [Int] {
        var seen = Set<Int>()
        return tokens(in: template).compactMap { token in
            guard case .date(let dayOffset) = token.placeholder, seen.insert(dayOffset).inserted
            else { return nil }
            return dayOffset
        }
    }

    /// The clipboard offsets to read before filling, each once, in order.
    public static func clipboardOffsets(in template: String) -> [Int] {
        var seen = Set<Int>()
        return tokens(in: template).compactMap { token in
            guard case .clipboard(let offset) = token.placeholder, seen.insert(offset).inserted
            else { return nil }
            return offset
        }
    }

    /// Whether it needs the fill sheet: a field to type or a date to pick.
    public static func needsFilling(_ template: String) -> Bool {
        !fields(in: template).isEmpty || !dateOffsets(in: template).isEmpty
    }

    public static func isTemplate(_ text: String) -> Bool {
        !tokens(in: text).isEmpty
    }

    /// How a date placeholder reads in the sheet.
    public static func dateLabel(dayOffset: Int) -> String {
        switch dayOffset {
        case 0: "{date}"
        case 1...: "{date +\(dayOffset)d}"
        default: "{date \(dayOffset)d}"
        }
    }

    public static func defaultDate(
        dayOffset: Int, now: Date = .now, calendar: Calendar = .current
    ) -> Date {
        calendar.date(byAdding: .day, value: dayOffset, to: now) ?? now
    }

    /// Fills every occurrence; a missing field falls back to its default, then
    /// to the empty string, so pasted output never keeps braces.
    public static func fill(_ template: String, values: [String: String]) -> String {
        render(template, values: values).text
    }

    /// The final text. `keepingDeferred` leaves the clipboard and the cursor as
    /// written, for a preview that must not read the clipboard.
    public static func render(
        _ template: String, values: [String: String] = [:], dates: [Int: Date] = [:],
        clipboard: [Int: String] = [:], keepingDeferred: Bool = false, now: Date = .now,
        calendar: Calendar = .current
    ) -> Rendered {
        var result = ""
        var cursorOffset: Int?
        var position = template.startIndex
        for token in tokens(in: template) {
            result += template[position..<token.range.lowerBound]
            position = token.range.upperBound
            let value: String
            switch token.placeholder {
            case .field(let name, let defaultValue):
                value = values[name] ?? defaultValue ?? ""
            case .date(let dayOffset):
                let date =
                    dates[dayOffset]
                    ?? defaultDate(dayOffset: dayOffset, now: now, calendar: calendar)
                value = date.formatted(date: .abbreviated, time: .omitted)
            case .clipboard(let offset):
                if keepingDeferred {
                    result += template[token.range]
                    continue
                }
                value = clipboard[offset] ?? ""
            case .cursor:
                if keepingDeferred {
                    result += template[token.range]
                } else if cursorOffset == nil {
                    cursorOffset = result.utf16.count
                }
                continue
            }
            result += token.modifiers.reduce(value) { $1.apply(to: $0) }
        }
        result += template[position...]
        return Rendered(
            text: result,
            charactersAfterCursor: cursorOffset.map {
                result[String.Index(utf16Offset: $0, in: result)...].count
            })
    }

    /// Where a `| modifier` goes for this caret: before the closing brace of the
    /// placeholder holding it or ending at it, in UTF-16 offsets. Nil elsewhere.
    public static func modifierInsertionPoint(in template: String, caret: Int) -> Int? {
        for token in tokens(in: template) where token.placeholder != .cursor {
            let start = token.range.lowerBound.utf16Offset(in: template)
            let end = token.range.upperBound.utf16Offset(in: template)
            if caret > start, caret <= end { return end - 1 }
        }
        return nil
    }
}

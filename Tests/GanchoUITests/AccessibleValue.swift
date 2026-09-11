import XCTest

/// Reading numbers back out of the accessibility tree, shared so every UI test
/// parses a rendered count the same way.
enum AccessibleValue {
    /// The element's value when it has one, its label otherwise: SwiftUI puts a
    /// `LabeledContent`'s number in the value and leaves the label as prose.
    @MainActor
    static func text(of element: XCUIElement) -> String {
        (element.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? element.label
    }

    /// The FIRST run of digits, so a string that also mentions another number
    /// ("13 months") can never be read as the count.
    static func firstInteger(in text: String) -> Int? {
        text.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.first
    }
}

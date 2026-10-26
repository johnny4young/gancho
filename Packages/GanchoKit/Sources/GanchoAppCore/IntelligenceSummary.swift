import ClipboardCore

/// Settings' Intelligence row at a glance: which of the four headline features
/// are on and which are off, in a fixed order.
public struct IntelligenceSummary: Equatable, Sendable {
    public enum Feature: CaseIterable, Sendable { case titles, meaning, screenshots, smartPaste }

    public let on: [Feature]
    public let off: [Feature]

    public init(_ preferences: IntelligencePreferences) {
        let states: [(Feature, Bool)] = [
            (.titles, preferences.intelligentTitles), (.meaning, preferences.semanticSearch),
            (.screenshots, preferences.searchableScreenshots), (.smartPaste, preferences.smartPaste)
        ]
        on = states.filter(\.1).map(\.0)
        off = states.filter { !$0.1 }.map(\.0)
    }
}

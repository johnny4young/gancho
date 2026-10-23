import Foundation
import GanchoKit

extension PanelSearchModel {
    /// The field's four modes. Meaning is exclusive: a query in Meaning shows
    /// only the clips related by meaning.
    public var searchMode: PanelSearchMode {
        get { meaningEnabled ? .meaning : PanelSearchMode(mode) }
        set {
            // Meaning embeds the text as typed; a regex pattern has no meaning.
            mode = newValue.conventional ?? .fuzzy
            meaningEnabled = newValue == .meaning
        }
    }

    /// Clears every filter that narrows the list, tokens included.
    public func clearFilters() {
        kindFilter = .all
        selectedBoardID = nil
        selectedSourceAppBundleID = nil
        pinnedOnly = false
        deviceName = nil
        createdBefore = nil
    }

    /// Meaning hides while semantic search is off or Private Mode is on; a
    /// panel left in it would answer every query with nothing.
    public func meaningAvailabilityChanged(_ available: Bool) {
        if !available, searchMode == .meaning { searchMode = .fuzzy }
    }

    /// Sets the filter a token resolved to.
    public func apply(_ filter: SearchTokenFilter) {
        switch filter {
        case .app(let bundleID): selectedSourceAppBundleID = bundleID
        case .type(let kind): kindFilter = kind
        case .board(let id): selectedBoardID = id
        case .device(let name): deviceName = name
        case .before(let date): createdBefore = date
        }
    }

    /// Clears the filter a token set: its chip's ×.
    public func removeFilter(_ key: SearchTokenKey) {
        switch key {
        case .app: selectedSourceAppBundleID = nil
        case .type: kindFilter = .all
        case .board: selectedBoardID = nil
        case .device: deviceName = nil
        case .before: createdBefore = nil
        }
    }

    /// Moves each complete `key:value` word out of the query into its filter.
    /// The last word counts only once a space ends it, so typing is never cut.
    public func commitTokens(with parser: SearchTokenParser) {
        let words = query.split(whereSeparator: \.isWhitespace)
        guard words.contains(where: { $0.contains(":") }) else { return }
        let endsWord = query.last?.isWhitespace ?? false
        var kept: [Substring] = []
        for (index, word) in words.enumerated() {
            let isOpen = index == words.count - 1 && !endsWord
            if !isOpen, let filter = parser.filter(for: word) {
                apply(filter)
            } else {
                kept.append(word)
            }
        }
        guard kept.count != words.count else { return }
        let text = kept.joined(separator: " ")
        query = endsWord && !text.isEmpty ? text + " " : text
    }

    /// Tab: spells out a key, or applies the best value for `key:partial`.
    /// Returns false when there is nothing to complete, so Tab falls through.
    @discardableResult
    public func complete(with parser: SearchTokenParser) -> Bool {
        guard let completion = parser.completions(for: query).first else { return false }
        let word = SearchTokenParser.lastWord(of: query)
        let head = String(query[..<word.startIndex])
        switch completion {
        case .key(let key):
            query = head + key.spelling
        case .value(let key, let candidate):
            guard let filter = parser.filter(key, candidate) else { return false }
            apply(filter)
            query = head.trimmingCharacters(in: .whitespaces)
        }
        return true
    }
}

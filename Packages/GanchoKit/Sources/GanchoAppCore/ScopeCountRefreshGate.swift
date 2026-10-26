/// When a list load should recount the sidebar. A keystroke changes no
/// count, so a new query skips it; a reload of the same query, which only a
/// store change or a filter brings, recounts.
public struct ScopeCountRefreshGate: Sendable {
    private var lastQuery: String?

    public init() {}

    public mutating func shouldRecount(query: String) -> Bool {
        defer { lastQuery = query }
        return query.isEmpty || query == lastQuery
    }
}

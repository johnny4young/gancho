/// What the panel is doing, as far as the footer's key hints care.
public enum PanelFooterState: Sendable, Equatable {
    case list
    case actionPanel
    case stack
    /// The history itself is empty: nothing to pick or paste.
    case empty
    /// A query or filter emptied the list.
    case noMatches

    /// The action panel owns the keys while open; the stack replaces the peek.
    /// `listIsEmpty` means the list shows its empty state, not a search in flight.
    public static func resolve(
        actionPanelIsOpen: Bool, stackIsOpen: Bool, historyEmpty: Bool, narrowed: Bool,
        listIsEmpty: Bool
    ) -> Self {
        if actionPanelIsOpen { return .actionPanel }
        if stackIsOpen { return .stack }
        if historyEmpty, !narrowed { return .empty }
        if narrowed, listIsEmpty { return .noMatches }
        return .list
    }
}

/// One key hint in the footer's trailing group; the raw value names its
/// accessibility identifier.
public enum PanelFooterHint: String, Sendable {
    case alternative, eyedropper, pick, run, close, navigate, settings, keys
    case privateModeOff = "private-mode-off"
    case addToStack = "add-to-stack"
    case pasteNth = "paste-nth"

    /// The hints for `state`, in footer order. The dock shows its verbs' keys,
    /// so none repeats here.
    public static func hints(
        for state: PanelFooterState, hasAlternative: Bool = false, offersEyedropper: Bool = false,
        privateModeOff: Bool = false
    ) -> [Self] {
        var hints: [Self] = []
        // An alternative exists only over an empty list, and ↓ takes it.
        if hasAlternative { hints.append(.alternative) }
        if offersEyedropper, state == .list { hints.append(.eyedropper) }
        if privateModeOff { hints.append(.privateModeOff) }
        switch state {
        case .actionPanel: return [.pick, .run, .close]
        case .list: hints += [.navigate, .pasteNth]
        case .stack: hints += [.addToStack, .navigate]
        case .noMatches: hints.append(.navigate)
        case .empty: hints.append(.settings)
        }
        return hints + [.keys]
    }
}

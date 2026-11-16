/// Which of the peek dock's verbs stay in the row as it narrows. The view
/// tries each tier in order and keeps the first that fits; verbs a tier
/// leaves out move into the Actions list and keep their shortcuts.
public enum PeekDockFold {
    public struct Tier: Hashable, Sendable {
        /// The verbs in the row, in dock order.
        public let visible: [String]
        /// The first verb drops its target ("Paste" for "Paste into Figma").
        public let shortPrimary: Bool
    }

    /// Context leaves first, then Stack, then Pin and Board together, then
    /// the kind's own verb; Paste plain goes last. The first verb (Return)
    /// never folds.
    static let foldOrder: [Set<String>] = [
        ["preview-context"],
        ["preview-stack"],
        ["preview-pin", "preview-board"],
        ["preview-convert", "image-copy-text"],
        ["preview-paste-plain"]
    ]

    static let foldsBeforeShortening = "preview-context"

    /// The tiers, widest first. With a short name available the first verb
    /// gives up its target before the row gives up another verb, except
    /// Context, which folds into Actions first.
    public static func tiers(for ids: [String], primaryHasShortTitle: Bool = false) -> [Tier] {
        guard let primary = ids.first else { return [] }
        var rows = [ids]
        var hidden: Set<String> = []
        for step in foldOrder {
            hidden.formUnion(step)
            let visible = ids.filter { $0 == primary || !hidden.contains($0) }
            if visible != rows.last { rows.append(visible) }
        }
        return rows.enumerated().flatMap { index, row in
            let foldsFirst = index < rows.count - 1 && row.contains(foldsBeforeShortening)
            return [Tier(visible: row, shortPrimary: false)]
                + (primaryHasShortTitle && !foldsFirst
                    ? [Tier(visible: row, shortPrimary: true)] : [])
        }
    }
}

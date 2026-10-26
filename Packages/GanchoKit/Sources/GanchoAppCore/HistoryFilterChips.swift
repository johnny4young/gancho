import GanchoKit

/// The iPhone's active type and app filters, mirrored as removable chips under
/// the board rail. The board is not a chip: it already shows on the rail.
public enum HistoryFilterChip: Hashable, Sendable {
    case kind(ClipContentKind)
    case app(bundleID: String)

    public static func chips(kind: ClipContentKind?, appBundleID: String?) -> [HistoryFilterChip] {
        var chips: [HistoryFilterChip] = []
        if let kind { chips.append(.kind(kind)) }
        if let appBundleID, !appBundleID.isEmpty { chips.append(.app(bundleID: appBundleID)) }
        return chips
    }
}

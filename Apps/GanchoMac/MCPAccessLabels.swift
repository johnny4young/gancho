import Foundation
import GanchoDesign
import GanchoKit

/// The words for a grant's context, shared by MCP Access, the ledger and the
/// agent-read HUD.
enum MCPAccessLabels {
    static func timeScope(_ scope: MCPTimeScope) -> String {
        switch scope {
        case .lastHour: String(localized: "Last hour")
        case .lastDay: String(localized: "Last day")
        case .lastWeek: String(localized: "Last 7 days")
        case .lastMonth: String(localized: "Last 30 days")
        case .allTime: String(localized: "All time")
        }
    }

    /// "Board · window" as recorded at call time; boards are named as they are now.
    static func context(_ context: MCPAccessContext, boards: [Pinboard]) -> String {
        let selection: String
        if let boardID = context.boardID {
            selection =
                boards.first { $0.id == boardID }?.displayName
                ?? String(localized: "Deleted board")
        } else {
            selection = String(localized: "\(context.clipCount ?? 0) clips")
        }
        return "\(selection) · \(timeScope(context.timeScope))"
    }

    static func client(_ name: String?) -> String {
        name ?? String(localized: "Unknown client")
    }
}

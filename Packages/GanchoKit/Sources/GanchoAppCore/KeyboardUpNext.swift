import Foundation
import GanchoKit

/// Up next for the keyboard: the Mac's ranking over what this device's keyboard
/// inserted.
public enum KeyboardUpNext {
    /// One log for every app: iOS doesn't tell a keyboard which app hosts it.
    public static let logTarget = "com.johnny4young.gancho.keyboard"

    /// Logs one insert, and nothing at all while the switch is off.
    public static func logInsert(
        _ clipID: UUID, in log: any PasteEventLogging, isEnabled: Bool, now: Date = .now
    ) async {
        guard isEnabled else { return }
        try? await log.recordPasteEvents(clipIDs: [clipID], targetBundleID: logTarget, at: now)
    }

    /// The clip to offer on the plain recent list, never over its own first row.
    public static func clipID(
        events: [PasteEvent], isBrowsing: Bool, firstRowID: UUID?, now: Date = .now
    ) -> UUID? {
        guard let prediction = UpNextRanker.predict(events, now: now),
            UpNextVisibility(
                isEnabled: true, previewsHidden: false, isBrowsing: isBrowsing,
                firstRowID: firstRowID
            ).shows(prediction.clipID)
        else { return nil }
        return prediction.clipID
    }
}

import Foundation
import GanchoKit

/// Up next for the keyboard: the Mac's ranking over what this device's keyboard
/// inserted.
public enum KeyboardUpNext {
    /// One log for every app: iOS doesn't tell a keyboard which app hosts it.
    public static let logTarget = "com.johnny4young.gancho.keyboard"

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

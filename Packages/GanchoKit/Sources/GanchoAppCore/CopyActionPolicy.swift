import ClipboardCore
import Foundation
import GanchoKit

/// What the copy-time HUD offers for a capture.
public enum CopyAction: Equatable, Sendable {
    case color(ColorValue)
    case link(URL)
    case oneTimeCode
}

/// A whole-text verification code: 4–8 digits, or two groups of 3–4 digits
/// split by one space or hyphen.
public enum OneTimeCodeDetector {
    public static func matches(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let groups = trimmed.split(omittingEmptySubsequences: false) { $0 == " " || $0 == "-" }
        guard groups.allSatisfy({ group in group.allSatisfy { ("0"..."9").contains($0) } })
        else { return false }
        switch groups.count {
        case 1: return (4...8).contains(trimmed.count)
        case 2: return groups.allSatisfy { (3...4).contains($0.count) }
        default: return false
        }
    }
}

/// Decides whether a stored capture gets the copy-time HUD, and with what.
/// Vetoed copies never reach here: the monitor drops them before any read.
public enum CopyActionPolicy {
    /// A code offers to delete its clip, so only a clip this copy created
    /// qualifies: a recopy may have landed in a pinned or curated one.
    public static func action(
        for item: ClipItem, isNew: Bool, text: String?, switches: CopyActionSwitches,
        privateMode: Bool, sharingScreen: Bool
    ) -> CopyAction? {
        // Masking covers sensitive clips and the masked kinds (secret, card, token).
        guard switches.isEnabled, !privateMode, !sharingScreen, let text,
            !ClipSafePresentation.requiresMasking(item)
        else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch item.kind {
        case .color:
            guard switches.colors, let color = ColorValue.parse(trimmed) else { return nil }
            return .color(color)
        case .url:
            guard switches.links, let url = URL(string: trimmed),
                ["http", "https"].contains(url.scheme?.lowercased()), url.host() != nil
            else { return nil }
            return .link(url)
        default:
            guard switches.oneTimeCodes, isNew, OneTimeCodeDetector.matches(trimmed) else {
                return nil
            }
            return .oneTimeCode
        }
    }
}

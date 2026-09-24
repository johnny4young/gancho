import ClipboardCore
import Foundation
import GanchoAppCore
import GanchoKit

/// Intent/control and keyboard capture share the app's authorization and durable
/// ingestion contracts. This shell only supplies platform resources/preferences.
enum SharedCapture {
    typealias Outcome = IntentionalCaptureCoordinator.Outcome

    /// Device-local capture preferences live in the App Group so the app and its
    /// capture extensions read one copy. Without the group, defaults apply.
    static var preferences: UserDefaults {
        UserDefaults(suiteName: SharedInbox.appGroupID) ?? .standard
    }

    private static let adoptedLegacyPreferencesKey = "extension-preferences-adopted"

    /// Moves preferences saved by builds that kept them in the app's own
    /// defaults. Runs once; afterwards the App Group copy is authoritative.
    static func adoptLegacyPreferences(from legacy: UserDefaults) {
        let shared = preferences
        guard shared !== legacy, !shared.bool(forKey: adoptedLegacyPreferencesKey) else { return }
        IntelligencePreferences.load(from: legacy).save(to: shared)
        RetentionPolicy.load(from: legacy).save(to: shared)
        shared.set(true, forKey: adoptedLegacyPreferencesKey)
    }

    @MainActor
    static func saveCurrentClipboard() async -> Outcome {
        let defaults = preferences
        let read = await IntentionalPasteboardSource().captureNow()
        let intelligence = IntelligencePreferences.load(from: defaults)
        return await IntentionalCaptureCoordinator.save(
            read,
            configuration: .init(
                sensitiveLifetime: RetentionPolicy.load(from: defaults).sensitiveLifetime,
                detectSecrets: intelligence.detectSecrets,
                tier: .free, intelligence: intelligence,
                sourceDeviceName: DeviceProvenance.currentDeviceName()),
            openStore: { try IntentStore.open() })
    }

    /// The one confirmation wording for the keyboard and the Save Clipboard intent.
    static func message(for outcome: Outcome) -> LocalizedStringResource {
        switch outcome {
        case .saved(let saved) where !saved.isNew: "Already in your history."
        case .saved(let saved) where saved.item.kind == .image: "Saved the image to Gancho."
        case .saved: "Saved to Gancho."
        case .refused: "This clipboard item cannot be saved for privacy reasons."
        case .unavailable: "Couldn’t read the clipboard. Try pasting again."
        case .saveFailed: "Couldn’t save the clipboard. Try again."
        case .empty: "The clipboard is empty."
        case .storeUnavailable: "Couldn't open Gancho."
        }
    }
}

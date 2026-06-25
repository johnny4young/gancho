import AppIntents
import ClipboardCore
import GanchoKit

/// Shared between the iOS app and the widget extension (same source compiled
/// into both targets — App Intents that a Control or interactive widget runs
/// must have target membership in BOTH). Opens the App Group store and runs
/// the same classification pipeline the UI uses, so there is one capture path.
enum IntentStore {
    nonisolated static func open() throws -> GRDBClipboardStore {
        // The encrypted store's key lives in the shared keychain access group so
        // these extensions can read what the app wrote (see docs/ARCHITECTURE.md).
        try GRDBClipboardStore.encrypted(
            directory: SharedStorageLocation.storeDirectory(appGroupID: SharedInbox.appGroupID),
            keychainAccessGroup: KeychainPassphraseStore.iosSharedAccessGroup)
    }
}

/// Save whatever is on the pasteboard right now. The flagship capture path for
/// the Action Button, Back Tap, Shortcuts, the home-screen widget's save
/// button, and the Control Center "Save Clipboard" control.
struct SaveClipboardIntent: AppIntent {
    static let title: LocalizedStringResource = "Save Clipboard"
    static let description = IntentDescription(
        "Saves the current clipboard into Gancho. iOS shows its standard paste confirmation.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        switch await SharedCapture.saveCurrentClipboard() {
        case .savedImage: return .result(dialog: "Saved the image to Gancho.")
        case .savedText: return .result(dialog: "Saved to Gancho.")
        case .empty: return .result(dialog: "The clipboard is empty.")
        case .storeUnavailable: return .result(dialog: "Couldn't open Gancho.")
        }
    }
}

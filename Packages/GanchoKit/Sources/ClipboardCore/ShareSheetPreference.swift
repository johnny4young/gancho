import Foundation

/// Whether the share sheet saves at once, without showing what it will save.
/// Lives in the App Group defaults so the app sets it and the extension reads it.
public enum ShareSheetPreference {
    static let key = "share-sheet-saves-instantly"

    public static var defaults: UserDefaults {
        UserDefaults(suiteName: SharedInbox.appGroupID) ?? .standard
    }

    public static func savesInstantly(in defaults: UserDefaults = defaults) -> Bool {
        defaults.bool(forKey: key)
    }

    public static func setSavesInstantly(_ on: Bool, in defaults: UserDefaults = defaults) {
        defaults.set(on, forKey: key)
    }
}

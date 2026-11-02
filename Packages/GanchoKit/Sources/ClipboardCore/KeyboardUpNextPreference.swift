import Foundation

/// Whether the keyboard logs what it inserts and offers it next. Off unless
/// turned on. Lives in the App Group defaults so the app sets it and the
/// keyboard reads it.
public enum KeyboardUpNextPreference {
    static let key = "keyboard-up-next"

    public static var defaults: UserDefaults {
        UserDefaults(suiteName: SharedInbox.appGroupID) ?? .standard
    }

    public static func isEnabled(in defaults: UserDefaults = defaults) -> Bool {
        defaults.bool(forKey: key)
    }

    public static func setEnabled(_ on: Bool, in defaults: UserDefaults = defaults) {
        defaults.set(on, forKey: key)
    }
}

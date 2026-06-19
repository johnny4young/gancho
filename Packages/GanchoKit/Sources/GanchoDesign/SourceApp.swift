import Foundation

#if canImport(AppKit)
    import AppKit
#endif

/// Resolves a captured clip's `sourceAppBundleID` to a human label (and icon)
/// for the history's "From …" insight. The live name/icon come from
/// `NSWorkspace`; the pure `fallbackName` — used when the app is not installed
/// or resolvable, and in tests — derives a readable name from the bundle id.
public enum SourceApp {
    /// A readable name derived purely from a bundle id, e.g.
    /// `com.apple.Terminal` → `Terminal`: the last dot-separated segment,
    /// capitalized; the whole id when it has no dots.
    public static func fallbackName(forBundleID bundleID: String) -> String {
        let segment = bundleID.split(separator: ".").last.map(String.init) ?? bundleID
        guard let first = segment.first else { return bundleID }
        return first.uppercased() + segment.dropFirst()
    }

    #if canImport(AppKit)
        /// The installed app's Finder display name, falling back to
        /// `fallbackName` when the bundle id can't be resolved to an app.
        public static func displayName(forBundleID bundleID: String) -> String {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                var name = FileManager.default.displayName(atPath: url.path)
                if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
                if !name.isEmpty { return name }
            }
            return fallbackName(forBundleID: bundleID)
        }

        /// The installed app's icon, if the bundle id resolves to an app.
        public static func icon(forBundleID bundleID: String) -> NSImage? {
            guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            else { return nil }
            return NSWorkspace.shared.icon(forFile: url.path)
        }
    #endif
}

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
        // The NSWorkspace lookups below are synchronous and not free; the peek
        // resolves them on every selection change, so cache per bundle id to
        // keep keyboard/hover navigation smooth. Main-actor isolated: the only
        // callers are SwiftUI views.
        @MainActor private static var nameCache: [String: String] = [:]
        @MainActor private static var iconCache: [String: NSImage?] = [:]

        /// The installed app's Finder display name (cached), falling back to
        /// `fallbackName` when the bundle id can't be resolved to an app.
        @MainActor public static func displayName(forBundleID bundleID: String) -> String {
            if let cached = nameCache[bundleID] { return cached }
            var resolved = fallbackName(forBundleID: bundleID)
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                var name = FileManager.default.displayName(atPath: url.path)
                if name.hasSuffix(".app") { name = String(name.dropLast(4)) }
                if !name.isEmpty { resolved = name }
            }
            nameCache[bundleID] = resolved
            return resolved
        }

        /// The installed app's icon (cached), or nil when unresolvable.
        @MainActor public static func icon(forBundleID bundleID: String) -> NSImage? {
            if let cached = iconCache[bundleID] { return cached }
            let icon = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
                .map { NSWorkspace.shared.icon(forFile: $0.path) }
            iconCache[bundleID] = icon
            return icon
        }
    #endif
}

import Foundation

#if DEBUG
    /// QA-only overrides, compiled out of release builds entirely. Lets a
    /// device test exercise Pro-gated features (notably iCloud sync) without a
    /// StoreKit purchase — useful where there is no purchase UI (iOS) or where
    /// StoreKit testing transactions don't span devices.
    ///
    /// Enable per launch with the scheme argument `-gancho-force-pro` (handy on
    /// iOS, where there is no terminal), or persistently with
    /// `defaults write <bundle-id> gancho-force-pro -bool YES` (handy on macOS).
    /// Never compiled into a shipping build.
    public enum DebugFlags {
        public static var forcePro: Bool {
            UserDefaults.standard.bool(forKey: "gancho-force-pro")
                || CommandLine.arguments.contains("-gancho-force-pro")
        }
    }
#endif

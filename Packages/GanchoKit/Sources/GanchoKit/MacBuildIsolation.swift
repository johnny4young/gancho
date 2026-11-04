import Foundation

/// A Mac Debug build keeps its own history, sync state, keys and preferences, so
/// running it can't change the installed app's. It talks to CloudKit Development.
public enum MacBuildIsolation {
    public static let debugDefaultsSuite = "com.johnny4young.gancho.debug"

    public static var isIsolated: Bool {
        #if DEBUG && os(macOS)
            true
        #else
            false
        #endif
    }

    public static func storeFolderName(isIsolated: Bool = Self.isIsolated) -> String {
        isIsolated ? "Gancho-Debug" : "Gancho"
    }

    public static func keychainService(
        _ service: String, isIsolated: Bool = Self.isIsolated
    ) -> String {
        isIsolated ? "\(service).debug" : service
    }

    public static func launchDefaults(isIsolated: Bool = Self.isIsolated) -> UserDefaults {
        guard isIsolated else { return .standard }
        return UserDefaults(suiteName: debugDefaultsSuite) ?? .standard
    }
}

import Foundation
import Testing

/// Sync delivery configuration gate. Every assertion here pins a setting whose
/// regression BREAKS CROSS-DEVICE SYNC SILENTLY — no build error, no runtime
/// error, clips just stop arriving (it cost a full debugging day to trace each
/// one). Style mirrors `ReleaseMetadataTests`: read the committed files and
/// fail loudly when the wiring drifts.
@Suite("Sync delivery configuration")
struct SyncConfigTests {
    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // GanchoKitTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // GanchoKit
            .deletingLastPathComponent()  // Packages
            .deletingLastPathComponent()  // repo root
    }

    private static func text(_ components: String...) throws -> String {
        let url = components.reduce(repoRoot) { $0.appendingPathComponent($1) }
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// The push entitlement key DIFFERS per platform, and a mismatched key is
    /// silently DROPPED at signing: the app then runs with no push entitlement,
    /// CloudKit never notifies it of remote changes, and inbound sync goes
    /// quiet with zero errors anywhere.
    @Test func pushEntitlementKeysMatchTheirPlatforms() throws {
        let mac = try Self.text("Apps", "GanchoMac", "Gancho.entitlements")
        #expect(
            mac.contains("<key>com.apple.developer.aps-environment</key>"),
            "macOS must use com.apple.developer.aps-environment")
        #expect(
            !mac.contains("<key>aps-environment</key>"),
            "iOS's bare aps-environment key is silently dropped when signing a macOS app")

        let ios = try Self.text("Apps", "GanchoiOS", "Gancho.entitlements")
        #expect(
            ios.contains("<key>aps-environment</key>"),
            "iOS must use the bare aps-environment key")
        #expect(
            !ios.contains("<key>com.apple.developer.aps-environment</key>"),
            "macOS's prefixed key is not iOS's push entitlement")
    }

    /// project.yml regenerates the entitlements files (`make project`), so the
    /// source of truth must carry the same per-platform keys or the next
    /// generation reintroduces the mismatch.
    @Test func projectYAMLCarriesThePerPlatformPushKeys() throws {
        let project = try Self.text("project.yml")
        #expect(project.contains("com.apple.developer.aps-environment: development"))
        // The bare key must appear for iOS — and never with the macOS prefix
        // stripped/duplicated ambiguity: exactly one bare occurrence.
        let bareOccurrences = project.components(separatedBy: "\n").filter {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix("aps-environment:")
        }
        #expect(
            bareOccurrences.count == 1,
            "exactly ONE bare aps-environment (the iOS target); macOS uses the prefixed key")
    }

    /// CKSyncEngine only hears about remote changes while the process holds an
    /// APNs token — and NEITHER shell gets one reliably without asking:
    /// the macOS menu-bar agent (`.accessory`) never passes through the
    /// window-app activation path, and a fresh iOS install starts tokenless.
    @Test func bothShellsRegisterForRemoteNotificationsAtLaunch() throws {
        let mac = try Self.text("Apps", "GanchoMac", "GanchoMacApp.swift")
        #expect(
            mac.contains("registerForRemoteNotifications()"),
            "the macOS agent must request its APNs token explicitly at launch")

        let ios = try Self.text("Apps", "GanchoiOS", "GanchoiOSApp.swift")
        #expect(
            ios.contains("registerForRemoteNotifications()"),
            "iOS must request its APNs token explicitly at launch")
    }

    /// iOS receives CloudKit pushes in the background only with the
    /// remote-notification background mode.
    @Test func iOSDeclaresTheRemoteNotificationBackgroundMode() throws {
        let project = try Self.text("project.yml")
        #expect(project.contains("UIBackgroundModes"))
        #expect(project.contains("- remote-notification"))
    }

    /// The macOS agent is NOT a reliable APNs target even correctly configured,
    /// so its inbound delivery is the explicit pull: the poll timer plus
    /// `pollRemoteChanges` in the adapter's start(). Removing either quietly
    /// returns macOS to "sync only works right after a reset".
    @Test func macOSKeepsTheExplicitPullPath() throws {
        let appModel = try Self.text("Apps", "GanchoMac", "AppModel.swift")
        #expect(
            appModel.contains("scheduleSyncPoll()"),
            "the macOS shell must keep its periodic sync poll")

        let adapter = try Self.text(
            "Packages", "GanchoKit", "Sources", "GanchoSync", "CKSyncEngineAdapter.swift")
        #expect(
            adapter.contains("try await pollRemoteChanges()"),
            "start() must ask the server directly — the engine's own fetch is push-fed only")
    }
}

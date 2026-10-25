import Foundation
import GanchoAppCore
import GanchoKit

/// What the Settings › Privacy tiles say, read once per appearance. Counts,
/// sizes and flags only; never content.
struct PrivacyOverview: Equatable {
    var clips = 0
    var bytesOnDisk: Int64 = 0
    var protectedSkipsThisWeek = 0
    /// nil when there is no durable store to check.
    var encryption: StoreEncryptionReport?
}

extension AppModel {
    func privacyOverview(now: Date = .now) async -> PrivacyOverview {
        #if DEBUG
            // Snapshots pin the counts; a temporary store's size varies by run.
            if let fixed = Self.uiTestPrivacyOverview { return fixed }
        #endif
        var overview = PrivacyOverview()
        overview.clips = (try? await store.count()) ?? 0
        guard let fullStore else { return overview }
        overview.bytesOnDisk = await fullStore.diskUsage()
        overview.protectedSkipsThisWeek =
            (try? await fullStore.protectedSkips(lastDays: 7, now: now)) ?? 0
        overview.encryption = await fullStore.encryptionReport()
        return overview
    }

    #if DEBUG
        /// `-ui-test-privacy-overview <clips>:<bytes>:<skips>`, with a verified store.
        private static var uiTestPrivacyOverview: PrivacyOverview? {
            guard let index = CommandLine.arguments.firstIndex(of: "-ui-test-privacy-overview"),
                CommandLine.arguments.indices.contains(index + 1)
            else { return nil }
            let parts = CommandLine.arguments[index + 1].split(separator: ":").compactMap {
                Int64($0)
            }
            guard parts.count == 3 else { return nil }
            return PrivacyOverview(
                clips: Int(parts[0]), bytesOnDisk: parts[1], protectedSkipsThisWeek: Int(parts[2]),
                encryption: StoreEncryptionReport(
                    cipherVersion: "4.6.1", fileIsEncrypted: true, opensWithKey: true))
        }
    #endif

    /// The Privacy Center's Verify: re-reads the store on this Mac, no network.
    func verifyEncryption() async -> StoreEncryptionReport? {
        await fullStore?.encryptionReport()
    }

    /// The clips "Forget recent clips" would remove right now.
    func forgettableClips(_ window: ForgetRecentWindow) async -> [ClipItem] {
        guard let fullStore else { return [] }
        let clips = (try? await fullStore.forgettableClips(since: window.cutoff())) ?? []
        // A delete awaiting Undo is already gone from every list.
        return clips.filter { !pendingDeletionIDs.contains($0.id) }
    }

    /// Removes exactly the clips the user was shown, through the panel's
    /// undoable delete; a copy that landed after the count stays.
    func forget(_ clips: [ClipItem]) {
        delete(clips.filter { !pendingDeletionIDs.contains($0.id) })
    }
}

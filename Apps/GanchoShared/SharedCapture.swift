import ClipboardCore
import Foundation
import GanchoAppCore
import GanchoKit

/// Intent/control and keyboard capture share the app's authorization and durable
/// ingestion contracts. This shell only supplies platform resources/preferences.
enum SharedCapture {
    typealias Outcome = IntentionalCaptureCoordinator.Outcome

    @MainActor
    static func saveCurrentClipboard() async -> Outcome {
        guard let defaults = UserDefaults(suiteName: SharedInbox.appGroupID) else {
            return .storeUnavailable
        }
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

    /// Device-local settings, shared only with this device's capture extensions.
    @MainActor
    static func updatePreferences(retention: RetentionPolicy, intelligence: IntelligencePreferences)
    {
        guard let defaults = UserDefaults(suiteName: SharedInbox.appGroupID) else { return }
        retention.save(to: defaults)
        intelligence.save(to: defaults)
    }
}

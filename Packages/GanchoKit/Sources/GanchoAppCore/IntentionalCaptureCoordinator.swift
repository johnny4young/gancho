import ClipboardCore
import GanchoKit

/// Extension capture delegates classification, deduplication and persistence to
/// the app's coordinator. Success always contains the actual durable row.
public enum IntentionalCaptureCoordinator {
    public enum Outcome: Sendable {
        case saved(ClipIngestionCoordinator.Outcome)
        case refused
        case empty
        case unavailable
        case storeUnavailable
        case saveFailed
    }

    public static func save(
        _ read: IntentionalCaptureRead.Result,
        configuration: ClipIngestionCoordinator.Configuration,
        openStore: @Sendable () throws -> any ClipIngesting
    ) async -> Outcome {
        let capture: PasteboardCapture
        switch read {
        case .captured(let value, _): capture = value
        case .refused: return .refused
        case .empty: return .empty
        case .unavailable: return .unavailable
        }
        guard !Task.isCancelled else { return .unavailable }
        let store: any ClipIngesting
        do { store = try openStore() } catch { return .storeUnavailable }
        do {
            let outcome = try await ClipIngestionCoordinator().ingest(
                capture, configuration: configuration, store: store, syncEngine: NoopSyncEngine())
            return .saved(outcome)
        } catch {
            return .saveFailed
        }
    }
}

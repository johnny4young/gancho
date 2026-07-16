import Foundation
import GanchoKit
import TelemetryDeck

/// Deployment config for telemetry. One TelemetryDeck app covers every
/// platform of Gancho.
public enum GanchoTelemetryConfig {
    public static let appID = "47011A23-EF67-4337-BDC5-09A4121AE820"
}

/// `TelemetrySending` backed by TelemetryDeck. Lives in its own target so
/// the engine room never links a network SDK — the privacy boundary the
/// threat model relies on. It only ever forwards the already-bucketized
/// `(name, parameters)` a `TelemetryEvent` produces; by the event type's
/// design there is no field clipboard content could ride through.
public struct TelemetryDeckSender: TelemetrySending {
    /// Initializing configures the SDK once. Construct this ONLY when the
    /// user has explicitly opted in. Before consent no sender exists; after
    /// withdrawal `shutdown()` terminates the initialized SDK.
    public init(appID: String) {
        TelemetryDeck.initialize(config: TelemetryDeck.Config(appID: appID))
    }

    public func send(name: String, parameters: [String: String]) {
        TelemetryDeck.signal(name, parameters: parameters)
    }

    public func shutdown() {
        TelemetryDeck.terminate()
    }
}

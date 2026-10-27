import Foundation

/// One shared interpretation of whether the Foundation Models tier can run
/// here. Presentation consumes this value instead of re-implementing the
/// availability check.
///
/// The deterministic tiers (classification, OCR, secret detection, PII
/// redaction, semantic retrieval) do not consult this — they run everywhere.
public enum IntelligenceCapability: Equatable, Sendable {
    /// The on-device model can answer: Apple Intelligence is on and ready.
    case available
    /// Apple Intelligence is off, still downloading its assets, or unsupported
    /// on this hardware.
    case modelUnavailable

    public var canUseModel: Bool { self == .available }

    /// Launch argument that forces `.modelUnavailable`, so UI tests and
    /// snapshots don't depend on the host's Apple Intelligence state.
    public static let simulateModelUnavailableArgument = "-simulate-model-unavailable"

    public static func current(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> IntelligenceCapability {
        if arguments.contains(simulateModelUnavailableArgument) { return .modelUnavailable }
        return SmartPasteService.isAvailable ? .available : .modelUnavailable
    }
}

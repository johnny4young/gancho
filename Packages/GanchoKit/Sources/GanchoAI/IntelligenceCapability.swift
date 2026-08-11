import Foundation

/// One shared interpretation of whether the Foundation Models tier can run
/// here. Presentation consumes this value instead of re-implementing the
/// OS/version check, so "needs a newer macOS" and "Apple Intelligence is
/// switched off" stay distinguishable in the interface.
///
/// The deterministic tiers (classification, OCR, secret detection, PII
/// redaction, semantic retrieval) do not consult this — they run everywhere.
public enum IntelligenceCapability: Equatable, Sendable {
    /// The on-device model can answer: OS 26+ and Apple Intelligence ready.
    case available
    /// This OS predates the Foundation Models tier entirely (macOS < 26), so
    /// model-backed features cannot exist here — not a setting the user could
    /// change. iOS never reports this: the iOS floor is already 26.
    case requiresMacOS26
    /// The OS has the tier, but Apple Intelligence is off, still downloading
    /// its assets, or unsupported on this hardware.
    case modelUnavailable

    public var canUseModel: Bool { self == .available }

    /// Launch argument that forces the pre-26 answer, so a UI test can cover
    /// the supported Sequoia floor deterministically on any host OS.
    public static let simulateSequoiaArgument = "-simulate-sequoia-capabilities"

    public static func current(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> IntelligenceCapability {
        #if os(macOS)
            if arguments.contains(simulateSequoiaArgument) { return .requiresMacOS26 }
        #endif
        guard #available(macOS 26.0, iOS 26.0, *) else { return .requiresMacOS26 }
        return SmartPasteService.isAvailable ? .available : .modelUnavailable
    }
}

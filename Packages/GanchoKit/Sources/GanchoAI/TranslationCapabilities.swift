import Foundation

/// Shared menu policy. Native translation assets are independent of the generative model.
public struct TranslationDestination: Sendable, Equatable, Identifiable {
    public let code: String
    public let status: TranslationPairStatus
    public let modelAvailable: Bool
    public var id: String { code }
    public var isAvailable: Bool { status == .installed || modelAvailable }

    public init(code: String, status: TranslationPairStatus, modelAvailable: Bool) {
        self.code = code
        self.status = status
        self.modelAvailable = modelAvailable
    }
}

public enum TranslationCapabilities {
    public static let targetCodes = ["en", "es", "fr", "de", "it", "pt", "ja", "ko", "zh"]

    /// No downloads or sessions are started while building the menu.
    public static func destinations(
        text: String, enabled: Bool, engines: TranslationEngines = .live
    ) async throws -> [TranslationDestination] {
        try Task.checkCancellation()
        guard enabled, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        let source = engines.identifySource(SmartPasteService().prepared(text))
        var destinations: [TranslationDestination] = []
        for code in targetCodes
        where source?.languageCode != Locale.Language(identifier: code).languageCode {
            try Task.checkCancellation()
            let status: TranslationPairStatus
            if let source {
                status = await engines.pairStatus(source, Locale.Language(identifier: code))
            } else {
                status = .undetermined
            }
            try Task.checkCancellation()
            destinations.append(
                TranslationDestination(
                    code: code, status: status, modelAvailable: engines.modelAvailable()))
        }
        return destinations
    }
}

public enum TranslationFailure: Error, Equatable {
    case noReadableResult
}

public struct TranslationAvailabilityRequest: Hashable, Sendable {
    public let text: String
    public let enabled: Bool
    public let modelAvailable: Bool
    public let refresh: Int

    public init(text: String, enabled: Bool, modelAvailable: Bool, refresh: Int) {
        self.text = text
        self.enabled = enabled
        self.modelAvailable = modelAvailable
        self.refresh = refresh
    }
}

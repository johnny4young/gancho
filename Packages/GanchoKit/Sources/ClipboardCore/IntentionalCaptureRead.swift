import Foundation

/// A user gesture permits a read, never overrides reserved pasteboard markers.
/// UIKit supplies these closures on the main actor; tests supply synthetic data.
public enum IntentionalCaptureRead {
    public struct Metadata: Equatable, Sendable {
        public let types: Set<String>
        public let changeCount: Int
        public let hasContent: Bool

        public init(types: Set<String>, changeCount: Int, hasContent: Bool) {
            self.types = types
            self.changeCount = changeCount
            self.hasContent = hasContent
        }

        public var isProtected: Bool {
            !types.isDisjoint(with: SensitivePasteboardTypes.captureVeto)
        }
    }

    public enum Result: Sendable, Equatable {
        case captured(PasteboardCapture, changeCount: Int)
        case refused
        case empty
        /// A denied, failed, cancelled or changed read is not an empty clipboard.
        case unavailable
    }

    @MainActor
    public static func read(
        metadata: () -> Metadata,
        payload: () async throws -> PasteboardCapture.Payload?
    ) async -> Result {
        let before = metadata()
        guard !before.isProtected else { return .refused }
        guard !Task.isCancelled else { return .unavailable }
        guard before.hasContent else { return .empty }
        do {
            let payload = try await payload()
            let after = metadata()
            guard !after.isProtected else { return .refused }
            guard before == after, !Task.isCancelled else { return .unavailable }
            guard let payload else { return .unavailable }
            if case .text(let text) = payload, text.isEmpty { return .empty }
            return .captured(
                PasteboardCapture(
                    payload: payload,
                    isFromUniversalClipboard: before.types.contains(
                        SensitivePasteboardTypes.remoteClipboard)),
                changeCount: before.changeCount)
        } catch {
            return .unavailable
        }
    }
}

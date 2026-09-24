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
            // Type lists can grow as promised data materialises; only a new
            // change count means the user's copy was replaced.
            guard before.changeCount == after.changeCount, !Task.isCancelled else {
                return .unavailable
            }
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

    /// A system paste delivers one provider per item. A marker anywhere, or a
    /// replaced clipboard, discards the whole batch; unsupported items are
    /// skipped and a single failed load does not discard its siblings.
    @MainActor
    public static func readBatch(
        count: Int,
        metadata: () -> Metadata,
        isSupported: (Int) -> Bool,
        payload: (Int) async throws -> PasteboardCapture.Payload?
    ) async -> [Result] {
        let initial = metadata()
        guard !initial.isProtected else { return [.refused] }
        guard count > 0 else { return [.empty] }
        let supported = (0..<count).filter(isSupported)
        guard !supported.isEmpty else { return [.unavailable] }
        var results: [Result] = []
        for index in supported {
            let result = await read(metadata: metadata, payload: { try await payload(index) })
            let current = metadata()
            if result == .refused || current.isProtected { return [.refused] }
            guard current.changeCount == initial.changeCount, !Task.isCancelled else {
                return [.unavailable]
            }
            results.append(result)
        }
        return results
    }
}

import Foundation
import Observation

/// One transient, explicitly requested OCR result. Nothing here persists,
/// enriches or syncs. Even an uncooperative recognizer cannot copy after cancel
/// or supersession, and a later user copy always wins over automatic delivery.
@Observable @MainActor
public final class ManualOCRSession {
    public enum State: Sendable, Equatable {
        case idle, recognizing, copied, ready, noText, unavailable, failed
    }

    public enum ReviewedCopyResult: Sendable, Equatable {
        case copied, clipboardChanged, unavailable
    }

    public private(set) var state: State = .idle
    public private(set) var text = ""
    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var generation = UUID()
    @ObservationIgnored private var permitsResult: @Sendable () async -> Bool = { false }

    public var requestID: UUID { generation }

    public init() {}

    public func cancel() {
        generation = UUID()
        task?.cancel()
        task = nil
        text = ""
        state = .idle
        permitsResult = { false }
    }

    public func start(
        recognize: @escaping @Sendable () async throws -> String?,
        isAllowed: @escaping @Sendable () async -> Bool,
        clipboardRevision: @escaping @MainActor () -> Int,
        copy: @escaping @MainActor (String) -> Void,
        didFinish: @escaping @MainActor (State) -> Void
    ) {
        cancel()
        let request = generation
        let revision = clipboardRevision()
        permitsResult = isAllowed
        state = .recognizing
        task = Task { [weak self] in
            do {
                guard await isAllowed() else {
                    self?.finish(.unavailable, request: request, notify: didFinish)
                    return
                }
                try Task.checkCancellation()
                let result = try await recognize()
                try Task.checkCancellation()
                guard await isAllowed() else {
                    self?.finish(.unavailable, request: request, notify: didFinish)
                    return
                }
                guard let self, request == self.generation, !Task.isCancelled else { return }
                guard let result, !result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else {
                    self.finish(.noText, request: request, notify: didFinish)
                    return
                }
                self.text = result
                if revision == clipboardRevision() {
                    copy(result)
                    self.finish(.copied, request: request, notify: didFinish)
                } else {
                    self.finish(.ready, request: request, notify: didFinish)
                }
            } catch is CancellationError {
                if let self, request == self.generation { self.cancel() }
            } catch {
                self?.finish(.failed, request: request, notify: didFinish)
            }
        }
    }

    /// Review edits stay transient. Revalidate immediately before the explicit
    /// action so a deleted, expired or newly protected source cannot be reused.
    public func reviewedText(_ edited: String) async -> String? {
        let request = generation
        guard state == .copied || state == .ready, await permitsResult(),
            request == generation, !Task.isCancelled,
            !edited.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        return edited
    }

    /// Explicit copy may still wait for a storage permission check. Preserve
    /// anything copied during that wait and keep the draft available to retry.
    public func copyReviewedText(
        _ edited: String, clipboardRevision: @MainActor () -> Int,
        copy: @MainActor (String) -> Void
    ) async -> ReviewedCopyResult {
        let revision = clipboardRevision()
        guard let text = await reviewedText(edited) else { return .unavailable }
        guard revision == clipboardRevision() else { return .clipboardChanged }
        copy(text)
        return .copied
    }

    private func finish(_ result: State, request: UUID, notify: (State) -> Void) {
        guard request == generation, !Task.isCancelled else { return }
        state = result
        task = nil
        notify(result)
    }
}

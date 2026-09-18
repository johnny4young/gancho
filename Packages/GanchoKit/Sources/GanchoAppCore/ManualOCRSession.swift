import Foundation
import GanchoAI
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
    /// The lines behind `text`, in reading order, with their regions when
    /// recognition produced them. A surface can draw them over the image.
    public private(set) var lines: [RecognizedTextLine] = []
    /// The clip this request belongs to, so a surface shows the result beside
    /// the right item and nowhere else.
    public private(set) var itemID: UUID?
    /// Recognition found something the secret detector flags. Such text is
    /// NEVER copied automatically: every copy is an explicit action after a
    /// reveal, the same contract sensitive clips already have.
    public private(set) var isSensitive = false
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
        lines = []
        itemID = nil
        isSensitive = false
        state = .idle
        permitsResult = { false }
    }

    public func start(
        itemID: UUID? = nil,
        recognize: @escaping @Sendable () async throws -> ManualOCRResult?,
        isAllowed: @escaping @Sendable () async -> Bool,
        isSensitive detectSecret: @escaping @Sendable (String) -> Bool = { _ in false },
        clipboardRevision: @escaping @MainActor () -> Int,
        copy: @escaping @MainActor (String) -> Void,
        didFinish: @escaping @MainActor (State) -> Void
    ) {
        cancel()
        let request = generation
        self.itemID = itemID
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
                guard let result, !result.isEmpty else {
                    self.finish(.noText, request: request, notify: didFinish)
                    return
                }
                self.lines = result.lines
                self.text = result.text
                let sensitive = detectSecret(result.text)
                self.isSensitive = sensitive
                if !sensitive, revision == clipboardRevision() {
                    copy(result.text)
                    self.finish(.copied, request: request, notify: didFinish)
                } else {
                    self.finish(.ready, request: request, notify: didFinish)
                }
            } catch is CancellationError {
                if let self, request == self.generation { self.cancel() }
            } catch ManualImageTextError.unavailable {
                // The source vanished, expired or became protected between the
                // permission check and the read. That is NOT a recognition
                // failure: telling the user to try another image would be wrong
                // advice about an image that is simply gone.
                self?.finish(.unavailable, request: request, notify: didFinish)
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

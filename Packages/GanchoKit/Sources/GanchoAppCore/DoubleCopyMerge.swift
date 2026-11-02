import ClipboardCore
import Foundation
import GanchoAI
import GanchoKit

/// One text copy as the monitor saw it.
public struct CopyObservation: Equatable, Sendable {
    public let text: String
    public let sourceAppBundleID: String?
    public let change: PasteboardCapture.ChangeStamp

    public init(text: String, sourceAppBundleID: String?, change: PasteboardCapture.ChangeStamp) {
        self.text = text
        self.sourceAppBundleID = sourceAppBundleID
        self.change = change
    }

    /// Plain text with a monitor stamp; anything else never merges.
    public init?(_ capture: PasteboardCapture) {
        guard let change = capture.change, case .text(let text) = capture.payload,
            !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        self.init(text: text, sourceAppBundleID: capture.sourceAppBundleID, change: change)
    }
}

/// The same text copied twice from the same app, as the very next change and
/// inside the window. A change folded into one poll never counts: the copy
/// between them was never seen.
public enum DoubleCopyDetector {
    public static let window: TimeInterval = 0.6

    public static func isDoubleCopy(
        _ current: CopyObservation, after previous: CopyObservation
    )
        -> Bool
    {
        current.text == previous.text
            && current.sourceAppBundleID == previous.sourceAppBundleID
            && current.change.count == previous.change.count + 1
            && (0...window).contains(
                current.change.observedAt.timeIntervalSince(previous.change.observedAt))
    }
}

/// Remembers which clip each capture landed in, so a double copy knows the
/// clip to append to and the throwaway clip its first copy made.
public struct DoubleCopyMerger: Sendable {
    public enum Decision: Equatable, Sendable {
        case ingest
        /// Append `text` to `target`; `discard` is the clip the first copy created.
        case merge(text: String, target: UUID, discard: UUID?)
    }

    private struct Pending: Sendable {
        let observation: CopyObservation
        let priorClipID: UUID?
        let createdClipID: UUID?
    }

    /// The clip the latest capture or merge landed in.
    private var newestClipID: UUID?
    private var pending: Pending?

    public init() {}

    public func decide(_ observation: CopyObservation?) -> Decision {
        guard let observation, let pending, let target = pending.priorClipID,
            DoubleCopyDetector.isDoubleCopy(observation, after: pending.observation)
        else { return .ingest }
        return .merge(text: observation.text, target: target, discard: pending.createdClipID)
    }

    /// A capture was stored as `clipID`. Only a fresh, plain clip can pair
    /// with the next copy, and never with itself.
    public mutating func didIngest(
        _ observation: CopyObservation?, clipID: UUID, isNew: Bool, canPair: Bool
    ) {
        let prior = newestClipID
        newestClipID = clipID
        pending = observation.flatMap {
            canPair && prior != clipID
                ? Pending(observation: $0, priorClipID: prior, createdClipID: isNew ? clipID : nil)
                : nil
        }
    }

    /// The merge landed: the next double copy appends to the same clip.
    public mutating func didMerge(into target: UUID) {
        newestClipID = target
    }
}

/// Appends a double copy to the clip before it, re-checking the merged text
/// for secrets and masked kinds, then drops the clip the first copy created.
public struct ClipMergeWorkflow: Sendable {
    public enum Outcome: Equatable, Sendable {
        case merged(ClipItem, text: String, partCount: Int)
        case refused
    }

    private let classifier: RuleClassifier
    private let detector: SensitiveDataDetector

    public init(
        classifier: RuleClassifier = RuleClassifier(),
        detector: SensitiveDataDetector = SensitiveDataDetector()
    ) {
        self.classifier = classifier
        self.detector = detector
    }

    public func merge(
        _ text: String, into target: UUID, discarding discard: UUID?,
        store: any ClipReading & ClipMerging, deletion: @Sendable ([UUID]) async -> Void,
        engine: any SyncEngine
    ) async -> Outcome {
        guard let item = try? await store.item(id: target), !item.isSensitive,
            !ClipSafePresentation.requiresMasking(item), item.kind.allowsTextEditing,
            case .text(let current)? = try? await store.content(for: target)
        else { return .refused }
        let existing = item.parts?.split(current) ?? [current]
        let separator = item.parts?.separator ?? .newline
        guard let (merged, parts) = ClipParts.join(existing + [text], separator: separator),
            detector.detect(merged) == nil
        else { return .refused }
        let kind = classifier.classify(merged)
        guard kind.allowsTextEditing,
            (try? await store.mergeClipText(
                id: target, expecting: current, text: merged, parts: parts, kind: kind)) == true,
            let updated = try? await store.item(id: target)
        else { return .refused }
        if let discard, discard != target { await deletion([discard]) }
        await engine.enqueue([updated])
        return .merged(updated, text: merged, partCount: parts.lengths.count)
    }
}

/// Drops uploads for clips that are gone, so a late enrichment of a clip a
/// merge (or the user) already deleted cannot re-queue it behind its delete.
public struct ExistingClipsSyncEngine: SyncEngine {
    private let base: any SyncEngine
    private let store: any ClipReading

    public init(_ base: any SyncEngine, store: any ClipReading) {
        self.base = base
        self.store = store
    }

    public func start() async throws { try await base.start() }
    public func stop() async { await base.stop() }

    public func enqueue(_ items: [ClipItem]) async {
        var existing: [ClipItem] = []
        for item in items where (try? await store.item(id: item.id)) != nil {
            existing.append(item)
        }
        guard !existing.isEmpty else { return }
        await base.enqueue(existing)
    }

    public func enqueueDeletion(ids: [UUID]) async { await base.enqueueDeletion(ids: ids) }
    public func enqueue(boards: [Pinboard]) async { await base.enqueue(boards: boards) }
    public func enqueueBoardDeletion(ids: [UUID]) async {
        await base.enqueueBoardDeletion(ids: ids)
    }
}

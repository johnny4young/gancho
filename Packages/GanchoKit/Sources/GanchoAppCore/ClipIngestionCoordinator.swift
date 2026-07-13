import ClipboardCore
import Foundation
import GanchoAI
import GanchoKit

/// Owns the platform-neutral capture workflow shared by the macOS and iOS
/// composition roots: payload mapping, persistence/deduplication, initial sync
/// enqueue, enrichment policy, enrichment IO, and the follow-up sync enqueue.
///
/// Platform shells retain only their mechanical effects: telemetry, list/widget
/// refresh, transient feedback, Live Activity presentation, and the macOS free
/// title-taste counter. The coordinator imports no UI, telemetry, or transport.
public struct ClipIngestionCoordinator: Sendable {
    public struct Configuration: Sendable {
        public var sensitiveLifetime: TimeInterval
        public var detectSecrets: Bool
        public var precomputedKind: ClipContentKind?
        public var tier: UserTier
        public var intelligence: IntelligencePreferences
        public var allowsFreeTitle: Bool

        public init(
            sensitiveLifetime: TimeInterval = 600,
            detectSecrets: Bool = true,
            precomputedKind: ClipContentKind? = nil,
            tier: UserTier,
            intelligence: IntelligencePreferences,
            allowsFreeTitle: Bool = false
        ) {
            self.sensitiveLifetime = sensitiveLifetime
            self.detectSecrets = detectSecrets
            self.precomputedKind = precomputedKind
            self.tier = tier
            self.intelligence = intelligence
            self.allowsFreeTitle = allowsFreeTitle
        }
    }

    public struct EnrichmentDecision: Sendable, Equatable {
        public let plan: EnrichmentPlan
        public let writesTitle: Bool
        public let usesFreeTitle: Bool

        public var isEmpty: Bool { plan.isEmpty && !writesTitle }
    }

    public struct Outcome: Sendable {
        /// The durable row. On deduplication this is the existing row moved to
        /// the top, not the proposed throwaway identifier.
        public let item: ClipItem
        public let content: ClipContent?
        public let isNew: Bool
        /// Content-free size used by telemetry bucket selection in the shell.
        public let contentLength: Int
        public let enrichment: EnrichmentDecision
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

    /// Maps and persists one capture, then enqueues exactly the row returned by
    /// the store. Errors propagate so callers never present a failed write as a
    /// duplicate or enqueue a proposed row that does not exist.
    public func ingest(
        _ capture: PasteboardCapture,
        configuration: Configuration,
        store: any ClipIngesting,
        syncEngine: any SyncEngine
    ) async throws -> Outcome {
        let (proposed, content) = ClipItemFactory.make(
            from: capture,
            classifier: classifier,
            detector: detector,
            sensitiveLifetime: configuration.sensitiveLifetime,
            detectSecrets: configuration.detectSecrets,
            precomputedKind: configuration.precomputedKind)
        let stored = try await store.insert(proposed, content: content)
        await syncEngine.enqueue([stored])

        let plan = EnrichmentPlan(
            content: content,
            kind: stored.kind,
            isSensitive: stored.isSensitive,
            hasTitle: !stored.title.isEmpty,
            isPro: configuration.tier == .pro,
            preferences: configuration.intelligence)
        let freeTitle =
            configuration.allowsFreeTitle
            && configuration.tier != .pro
            && !stored.isSensitive
            && stored.title.isEmpty
            && content?.isText == true

        return Outcome(
            item: stored,
            content: content,
            isNew: stored.id == proposed.id,
            contentLength: Self.contentLength(content, fallback: stored.preview),
            enrichment: EnrichmentDecision(
                plan: plan,
                writesTitle: plan.runs(.title) || freeTitle,
                usesFreeTitle: freeTitle))
    }

    /// Runs the planned on-device work and pushes its persisted fruits through
    /// sync. `syncEngine` is nil when sync is disabled.
    ///
    /// The follow-up enqueue only fires for stages that write a SYNCED column:
    /// the title (including the macOS free-title taste) and OCR both set
    /// `needsUpload`. Embeddings live in `clip_embedding` and are not part of
    /// `ClipItem`'s transport representation, so an embedding-only enrichment
    /// must not schedule a CloudKit upload — otherwise the enqueue's
    /// `markNeedsUpload` would re-upload a clip whose synced content never
    /// changed.
    public func enrich(
        _ outcome: Outcome,
        store: any ClipEnriching,
        syncEngine: (any SyncEngine)?,
        onTitleWritten: @escaping @Sendable () async -> Void
    ) async {
        guard !outcome.enrichment.isEmpty else { return }
        await EnrichmentService().enrich(
            outcome.item,
            content: outcome.content,
            plan: outcome.enrichment.plan,
            writeTitle: outcome.enrichment.writesTitle,
            store: store,
            onTitleWritten: onTitleWritten)
        let wroteSyncedField =
            outcome.enrichment.writesTitle || outcome.enrichment.plan.runs(.ocr)
        if wroteSyncedField, let syncEngine {
            await syncEngine.enqueue([outcome.item])
        }
    }

    private static func contentLength(_ content: ClipContent?, fallback: String) -> Int {
        switch content {
        case .text(let text): text.count
        case .binary(let data, _): data.count
        case .fileReferences(let paths): paths.joined(separator: "\n").count
        case nil: fallback.count
        }
    }
}

extension ClipContent {
    fileprivate var isText: Bool {
        if case .text = self { return true }
        return false
    }
}

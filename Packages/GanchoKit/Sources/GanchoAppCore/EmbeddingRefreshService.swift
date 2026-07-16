import ClipboardCore
import Foundation
import GanchoAI
import GanchoKit

/// The store surface the background embedding refresh needs. A narrow
/// GanchoAppCore protocol (the `PanelSearchSource` pattern) rather than a
/// frozen-contract addition: the refresh pass is an internal maintenance
/// detail, not client API. `GRDBClipboardStore` satisfies it as-is.
public protocol EmbeddingRefreshSource: Sendable {
    /// One bounded batch of clip ids whose vector predates the current model.
    func staleEmbeddingClipIDs(limit: Int) async throws -> [UUID]
    /// Full content — re-embedding needs the text, not the 120-char preview.
    func content(for id: UUID) async throws -> ClipContent?
    /// Stores the fresh vector, stamped with the current model version.
    func saveEmbedding(clipID: UUID, vector: [Float]) async throws
}

extension GRDBClipboardStore: EmbeddingRefreshSource {}

/// Re-embeds clips whose stored vector predates
/// `EmbeddingModelInfo.currentVersion`, so a model upgrade converges the whole
/// history without blocking capture or the first panel open. The shells run it
/// at utility priority after launch settles; it re-checks the environment
/// around every item (task cancellation, thermal pressure, Low Power Mode) and
/// skips entirely when the model assets are not on device. Progress lives in
/// the rows themselves — each refreshed row stops being stale — so an
/// interrupted pass resumes exactly where it left off on the next launch, with
/// no bookkeeping of its own. While the pipeline version is unchanged nothing
/// is stale and the pass is a no-op.
public struct EmbeddingRefreshService: Sendable {
    /// Matches `EnrichmentService`'s ingest-time truncation, so refreshed
    /// vectors are comparable to the ones written at capture.
    static let inputLimit = 1_000
    /// Small batches keep every read bounded and make the environment
    /// re-checks frequent.
    static let batchSize = 16

    private let makeEmbedder: @Sendable () -> (any TextEmbedding)?
    private let isEnvironmentSuitable: @Sendable () -> Bool

    /// Production configuration: the contextual embedder (only when its model
    /// assets are already on device — this pass never triggers a download) and
    /// the thermal/power gates.
    public init() {
        self.init(
            makeEmbedder: {
                guard let embedder = ContextualSentenceEmbedder(),
                    embedder.hasAvailableAssets
                else { return nil }
                return embedder
            },
            isEnvironmentSuitable: {
                let process = ProcessInfo.processInfo
                let thermal = process.thermalState
                return (thermal == .nominal || thermal == .fair)
                    && !process.isLowPowerModeEnabled
            })
    }

    /// Test seam: scripted embedder and environment.
    init(
        makeEmbedder: @escaping @Sendable () -> (any TextEmbedding)?,
        isEnvironmentSuitable: @escaping @Sendable () -> Bool
    ) {
        self.makeEmbedder = makeEmbedder
        self.isEnvironmentSuitable = isEnvironmentSuitable
    }

    /// Runs the refresh until nothing is stale, the task is cancelled, or the
    /// environment turns hostile. Returns how many clips were re-embedded.
    @discardableResult
    public func run(store: any EmbeddingRefreshSource) async -> Int {
        guard let embedder = makeEmbedder() else { return 0 }
        var refreshed = 0
        while !Task.isCancelled, isEnvironmentSuitable() {
            guard let batch = try? await store.staleEmbeddingClipIDs(limit: Self.batchSize),
                !batch.isEmpty
            else { break }
            var progressed = false
            for id in batch {
                if Task.isCancelled || !isEnvironmentSuitable() { return refreshed }
                guard case .text(let text)? = try? await store.content(for: id),
                    let vector = try? embedder.vector(for: String(text.prefix(Self.inputLimit))),
                    (try? await store.saveEmbedding(clipID: id, vector: vector)) != nil
                else { continue }
                refreshed += 1
                progressed = true
            }
            // A batch that refreshed nothing would come back identical forever
            // (failed rows stay stale); stop and let a later launch retry.
            guard progressed else { break }
        }
        return refreshed
    }
}

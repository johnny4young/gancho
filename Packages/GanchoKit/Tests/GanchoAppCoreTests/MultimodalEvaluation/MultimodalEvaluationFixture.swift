import Foundation
import GRDB
import GanchoAI
@_spi(GanchoInternal) import GanchoKit

@testable import GanchoAppCore

/// A disposable store seeded the way enrichment seeds it: real Vision OCR, and
/// secret-looking OCR text dropped before it becomes searchable.
final class MultimodalEvaluationFixture {
    let store: GRDBClipboardStore
    let blobDirectory: URL
    /// Text bodies plus stored OCR text. An image is absent when OCR read nothing
    /// or its text was dropped as a secret.
    let searchableText: [UUID: String]
    let imageIDs: Set<UUID>

    private init(
        store: GRDBClipboardStore, blobDirectory: URL, searchableText: [UUID: String],
        imageIDs: Set<UUID>
    ) {
        self.store = store
        self.blobDirectory = blobDirectory
        self.searchableText = searchableText
        self.imageIDs = imageIDs
    }

    deinit { try? FileManager.default.removeItem(at: blobDirectory) }

    static func make(
        captures: [MultimodalEvaluationCorpus.Capture],
        configure: (inout ClipItem) -> Void = { _ in }
    ) async throws -> MultimodalEvaluationFixture {
        let blobDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "multimodal-evaluation-\(UUID())")
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(), blobs: BlobStore(directory: blobDirectory))
        try store.migrate()
        var searchableText: [UUID: String] = [:]
        var imageIDs: Set<UUID> = []
        for capture in captures {
            if case .text(let body) = capture.scene {
                var item = ClipItem(id: capture.id, preview: body, contentHash: capture.key)
                configure(&item)
                try await store.insert(item, content: .text(body))
                searchableText[capture.id] = body
                continue
            }
            let png = try SyntheticCaptureRenderer.png(for: capture.scene)
            // A neutral preview keeps the answer out of every field except OCR text.
            var item = ClipItem(
                id: capture.id, kind: .image, preview: "Image", contentHash: capture.key)
            configure(&item)
            try await store.insert(item, content: .binary(data: png, typeIdentifier: "public.png"))
            imageIDs.insert(capture.id)
            if let extracted = try await ImageTextExtractor().extractText(from: png),
                let stored = EnrichmentService.storableExtractedText(extracted)
            {
                try await store.attachExtractedText(id: capture.id, text: stored)
                searchableText[capture.id] = stored
            }
        }
        return MultimodalEvaluationFixture(
            store: store, blobDirectory: blobDirectory, searchableText: searchableText,
            imageIDs: imageIDs)
    }
}

/// One way of answering a query. A native visual candidate joins the comparison
/// by conforming here; nothing in the shipping targets depends on this seam.
protocol MultimodalRetrievalStrategy {
    var name: String { get }
    func rank(_ text: String, limit: Int) async throws -> [UUID]
}

/// Conventional fuzzy search over stored OCR text and text bodies. Sensitive rows
/// are vetoed, as any route that may hand results to an agent must do.
struct OCRLexicalStrategy: MultimodalRetrievalStrategy {
    let store: GRDBClipboardStore
    let name = "ocr-lexical"

    func rank(_ text: String, limit: Int) async throws -> [UUID] {
        try await store.search(
            ClipSearchQuery(text: text, excludesSensitive: true), limit: limit
        ).map(\.id)
    }
}

/// Lexical results first, then related ids from the current Apple contextual
/// model over OCR text, mirroring `HybridSearchResult.ordered`. Production never
/// embeds image OCR; this strategy measures what doing so would add.
struct OCRSemanticStrategy<Embedder: TextEmbedding>: MultimodalRetrievalStrategy {
    let store: GRDBClipboardStore
    let embedder: Embedder
    let index: EmbeddingIndex
    let name = "ocr-apple-semantic"

    init(fixture: MultimodalEvaluationFixture, embedder: Embedder) throws {
        var index = EmbeddingIndex(dimension: embedder.dimension)
        // Sorted so insertion order, and with it tie-breaking, is stable across runs.
        for (id, text) in fixture.searchableText.sorted(by: { $0.key < $1.key }) {
            // Same input bound as enrichment's embedding pass.
            try index.insert(id: id, vector: embedder.vector(for: String(text.prefix(1_000))))
        }
        self.store = fixture.store
        self.embedder = embedder
        self.index = index
    }

    func rank(_ text: String, limit: Int) async throws -> [UUID] {
        let lexical = try await OCRLexicalStrategy(store: store).rank(text, limit: limit)
        // Rank everything, then filter, so ineligible rows cannot consume the limit:
        // the scoped SQL also applies its predicates before top-K.
        let related = try index.search(embedder.vector(for: text), topK: index.count).map(\.id)
        // `items(ids:)` already drops archived and expired rows.
        let visible = Set(
            try await store.items(ids: related).filter { !$0.isSensitive }.map(\.id))
        var seen = Set(lexical)
        let fresh = related.filter { visible.contains($0) && seen.insert($0).inserted }
        return Array((lexical + fresh).prefix(limit))
    }
}

/// Every text maps to the same vector, so ranking alone can never exclude a row.
struct ConstantEmbedding: TextEmbedding {
    let dimension = 4
    func vector(for text: String) throws -> [Float] { [1, 0, 0, 0] }
}

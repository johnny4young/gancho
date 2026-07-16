import Accelerate
import Foundation
import GRDB

/// The embedding PIPELINE's version — the model, its pooling, and the input
/// truncation together. Bump it when any of those changes: vectors written by
/// an older pipeline are not comparable to fresh query vectors, so queries
/// serve current-version rows only and the background refresh pass re-embeds
/// the rest. Existing rows are version 1 (the schema default).
public enum EmbeddingModelInfo {
    public static let currentVersion = 1
}

/// Persistence + query for semantic search: vectors live beside the clips,
/// the in-memory `EmbeddingIndex`-style scan happens at query time (linear
/// cosine is single-digit ms at history scale — measured in the AI spike).
extension GRDBClipboardStore {
    public func saveEmbedding(clipID: UUID, vector: [Float]) async throws {
        let data = vector.withUnsafeBufferPointer { Data(buffer: $0) }
        let dimension = vector.count
        try await writer.write { db in
            try db.execute(
                sql: """
                    INSERT OR REPLACE INTO clip_embedding
                      (clipID, dimension, vector, modelVersion)
                    VALUES (?, ?, ?, ?)
                    """,
                arguments: [
                    clipID.uuidString, dimension, data, EmbeddingModelInfo.currentVersion
                ])
        }
    }

    /// Clip IDs whose stored vector predates the current embedding pipeline —
    /// one bounded batch at a time, so the background refresh never holds a
    /// long read or materializes an unbounded id list. Archived clips are
    /// excluded: they are invisible to search, so re-embedding them would
    /// spend battery on rows no query can return. The sensitive exclusion is
    /// belt-and-suspenders — capture never embeds sensitive clips, but this
    /// query must not feed one to the re-embed loop even if some future path
    /// flips `isSensitive` after a vector exists.
    public func staleEmbeddingClipIDs(limit: Int) async throws -> [UUID] {
        // SQLite treats a negative LIMIT as "no limit" — the exact unbounded
        // read this API exists to prevent.
        guard limit > 0 else { return [] }
        return try await writer.read { db in
            try String.fetchAll(
                db,
                sql: """
                    SELECT e.clipID FROM clip_embedding e
                    JOIN clip c ON c.id = e.clipID
                    WHERE e.modelVersion < ? AND c.isArchived = 0 AND c.isSensitive = 0
                    LIMIT ?
                    """,
                arguments: [EmbeddingModelInfo.currentVersion, limit]
            ).compactMap(UUID.init(uuidString:))
        }
    }

    /// One stored vector, decoded inside the read closure: `Row` itself is not
    /// Sendable, so returning rows forces GRDB's synchronous `read` overload —
    /// which blocks a cooperative thread for the whole fetch. This box keeps
    /// the async overload available.
    private struct StoredEmbedding: Sendable {
        let id: String
        let vector: Data
    }

    /// Cosine top-K over stored vectors, joined back to visible clips.
    /// `snippetsOnly` scopes the same engine to the Library.
    public func semanticSearch(
        queryVector: [Float], topK: Int = 10, snippetsOnly: Bool = false
    ) async throws -> [ClipItem] {
        let rows = try await writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT e.clipID, e.vector FROM clip_embedding e
                    JOIN clip c ON c.id = e.clipID
                    WHERE c.isArchived = 0 AND e.dimension = ? AND e.modelVersion = ?
                    \(snippetsOnly ? "AND c.isSnippet = 1" : "")
                    """, arguments: [queryVector.count, EmbeddingModelInfo.currentVersion]
            ).map { StoredEmbedding(id: $0["clipID"], vector: $0["vector"]) }
        }
        guard !rows.isEmpty else { return [] }

        let queryNorm = sqrt(vDSP.sumOfSquares(queryVector))
        guard queryNorm > 0 else { return [] }

        // Same cosine (dot / (‖v‖·‖q‖)) as before, but the per-row dot and
        // norm are vectorized via Accelerate — mirroring `EmbeddingIndex` —
        // so scores and ranking are unchanged, only faster.
        var scored: [(id: String, score: Float)] = []
        scored.reserveCapacity(rows.count)
        for row in rows {
            let vector = row.vector.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            guard vector.count == queryVector.count else { continue }
            var dot: Float = 0
            vector.withUnsafeBufferPointer { v in
                queryVector.withUnsafeBufferPointer { q in
                    vDSP_dotpr(
                        v.baseAddress!, 1, q.baseAddress!, 1, &dot,
                        vDSP_Length(v.count))
                }
            }
            let denominator = sqrt(vDSP.sumOfSquares(vector)) * queryNorm
            guard denominator > 0 else { continue }
            scored.append((row.id, dot / denominator))
        }
        let topIDs = scored.sorted { $0.score > $1.score }.prefix(topK).map(\.id)

        return try await writer.read { db in
            let fetched = try ClipRow.filter(keys: topIDs).fetchAll(db)
            let byID = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
            return topIDs.compactMap { byID[$0]?.item }
        }
    }
}

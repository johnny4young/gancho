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

    /// Cosine top-K over stored vectors, joined back to visible clips.
    /// `snippetsOnly` scopes the same engine to the Library.
    public func semanticSearch(
        queryVector: [Float], topK: Int = 10, snippetsOnly: Bool = false
    ) async throws -> [ClipItem] {
        let queryNorm = sqrt(vDSP.sumOfSquares(queryVector))
        guard queryNorm > 0 else { return [] }

        // Streamed, not materialized. `fetchAll` held every stored vector in
        // memory at once — 2 KB per clip, so 200 MB of `Data` at 100k rows —
        // and then allocated a fresh 512-element Swift array per row on top of
        // it, only to read each one once. A cursor visits them one at a time
        // and the dot product reads the BLOB's bytes where they already are,
        // so the resident cost is one row plus the scores.
        let scored = try await writer.read { db -> [(id: String, score: Float)] in
            var scored: [(id: String, score: Float)] = []
            let cursor = try Row.fetchCursor(
                db,
                sql: """
                    SELECT e.clipID, e.vector FROM clip_embedding e
                    JOIN clip c ON c.id = e.clipID
                    WHERE c.isArchived = 0 AND e.dimension = ? AND e.modelVersion = ?
                    \(snippetsOnly ? "AND c.isSnippet = 1" : "")
                    """, arguments: [queryVector.count, EmbeddingModelInfo.currentVersion])
            while let row = try cursor.next() {
                let id: String = row["clipID"]
                // Valid only for this step of the cursor, which is exactly how
                // long the scoring below needs it.
                let score = try row.withUnsafeData(named: "vector") { data -> Float? in
                    guard let data, data.count == queryVector.count * MemoryLayout<Float>.stride
                    else { return nil }
                    return data.withUnsafeBytes { raw -> Float? in
                        let stored = raw.bindMemory(to: Float.self)
                        guard let base = stored.baseAddress else { return nil }
                        var dot: Float = 0
                        var sumOfSquares: Float = 0
                        queryVector.withUnsafeBufferPointer { query in
                            vDSP_dotpr(
                                base, 1, query.baseAddress!, 1, &dot,
                                vDSP_Length(stored.count))
                        }
                        vDSP_svesq(base, 1, &sumOfSquares, vDSP_Length(stored.count))
                        let denominator = sqrt(sumOfSquares) * queryNorm
                        guard denominator > 0 else { return nil }
                        return dot / denominator
                    }
                }
                if let score { scored.append((id, score)) }
            }
            return scored
        }
        guard !scored.isEmpty else { return [] }

        let topIDs = Self.partialTopK(scored, count: topK).map(\.id)

        return try await writer.read { db in
            let fetched = try ClipRow.select(ClipRow.metadataColumns)
                .filter(keys: topIDs).fetchAll(db)
            let byID = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
            return topIDs.compactMap { byID[$0]?.item }
        }
    }

    /// Bounded O(n·k) selection of the `count` best scores, descending. The
    /// perf harness measured a full sort at ~30% of the 100k end-to-end cost
    /// (149ms) while this selection stays ~1/13th of that — and k is tiny
    /// (top-K ≤ ~10), so the insertion re-sort is effectively constant work.
    static func partialTopK(
        _ scored: [(id: String, score: Float)], count: Int
    ) -> [(id: String, score: Float)] {
        guard count > 0 else { return [] }
        var top: [(id: String, score: Float)] = []
        top.reserveCapacity(count + 1)
        for candidate in scored {
            if top.count < count {
                top.append(candidate)
                top.sort { $0.score > $1.score }
            } else if candidate.score > top[count - 1].score {
                top[count - 1] = candidate
                top.sort { $0.score > $1.score }
            }
        }
        return top
    }
}

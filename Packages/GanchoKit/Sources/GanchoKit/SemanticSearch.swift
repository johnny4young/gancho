import Foundation
import GRDB

/// Persistence + query for semantic search: vectors live beside the clips,
/// the in-memory `EmbeddingIndex`-style scan happens at query time (linear
/// cosine is single-digit ms at history scale — measured in the AI spike).
extension GRDBClipboardStore {
    public func saveEmbedding(clipID: UUID, vector: [Float]) async throws {
        let data = vector.withUnsafeBufferPointer { Data(buffer: $0) }
        let dimension = vector.count
        try await writer.write { db in
            try db.execute(
                sql:
                    "INSERT OR REPLACE INTO clip_embedding (clipID, dimension, vector) VALUES (?, ?, ?)",
                arguments: [clipID.uuidString, dimension, data])
        }
    }

    /// Cosine top-K over stored vectors, joined back to visible clips.
    /// `snippetsOnly` scopes the same engine to the Library.
    public func semanticSearch(
        queryVector: [Float], topK: Int = 10, snippetsOnly: Bool = false
    ) async throws -> [ClipItem] {
        let rows = try writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT e.clipID, e.vector FROM clip_embedding e
                    JOIN clip c ON c.id = e.clipID
                    WHERE c.isArchived = 0 AND e.dimension = ?
                    \(snippetsOnly ? "AND c.isSnippet = 1" : "")
                    """, arguments: [queryVector.count])
        }
        guard !rows.isEmpty else { return [] }

        let queryNorm = sqrt(queryVector.reduce(0) { $0 + $1 * $1 })
        guard queryNorm > 0 else { return [] }

        var scored: [(id: String, score: Float)] = []
        for row in rows {
            let id: String = row["clipID"]
            let data: Data = row["vector"]
            let vector = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
            var dot: Float = 0
            var norm: Float = 0
            for (a, b) in zip(vector, queryVector) {
                dot += a * b
                norm += a * a
            }
            let denominator = sqrt(norm) * queryNorm
            guard denominator > 0 else { continue }
            scored.append((id, dot / denominator))
        }
        let topIDs = scored.sorted { $0.score > $1.score }.prefix(topK).map(\.id)

        return try await writer.read { db in
            let fetched = try ClipRow.filter(keys: topIDs).fetchAll(db)
            let byID = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
            return topIDs.compactMap { byID[$0]?.item }
        }
    }
}

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
        try await semanticSearch(
            queryVector: queryVector, query: ClipSearchQuery(text: ""),
            topK: topK, snippetsOnly: snippetsOnly)
    }

    public func semanticSearch(
        queryVector: [Float], query: ClipSearchQuery, topK: Int = 10,
        snippetsOnly: Bool = false
    ) async throws -> [ClipItem] {
        try Task.checkCancellation()
        guard topK > 0 else { return [] }
        let queryNorm = sqrt(vDSP.sumOfSquares(queryVector))
        guard queryNorm > 0, queryNorm.isFinite else { return [] }

        // Streamed, not materialized. `fetchAll` held every stored vector in
        // memory at once — 2 KB per clip, so 200 MB of `Data` at 100k rows —
        // and then allocated a fresh 512-element Swift array per row on top of
        // it, only to read each one once. A cursor visits them one at a time
        // and the dot product reads the BLOB's bytes where they already are,
        // so the resident cost is one row plus the scores.
        let scored = try await writer.read { db -> [SemanticCandidate] in
            var top = BoundedTopK<SemanticCandidate>(limit: topK, by: Self.candidatePrecedes)
            let scope = Self.semanticScope(query, snippetsOnly: snippetsOnly)
            let cursor = try Row.fetchCursor(
                db,
                sql: "SELECT e.clipID, e.vector, clip.updatedAt FROM clip_embedding e "
                    + "JOIN clip ON clip.id = e.clipID " + scope.sql
                    + " AND e.dimension = ? AND e.modelVersion = ?",
                arguments: StatementArguments(
                    scope.arguments + [
                        queryVector.count, EmbeddingModelInfo.currentVersion
                    ]))
            while let row = try cursor.next() {
                try Task.checkCancellation()
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
                        guard denominator > 0, denominator.isFinite, dot.isFinite else {
                            return nil
                        }
                        return dot / denominator
                    }
                }
                if let score {
                    top.insert(SemanticCandidate(id: id, score: score, updatedAt: row["updatedAt"]))
                }
            }
            return top.sorted
        }
        try Task.checkCancellation()
        guard !scored.isEmpty else { return [] }

        return try await semanticMetadata(
            candidates: scored, query: query, snippetsOnly: snippetsOnly)
    }

    func semanticMetadata(
        candidates: [SemanticCandidate], query: ClipSearchQuery, snippetsOnly: Bool
    ) async throws -> [ClipItem] {
        let topIDs = candidates.map(\.id)
        let stamps = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, $0.updatedAt) })
        let items = try await writer.read { db in
            var scopeQuery = query
            let candidateIDs = Set(topIDs.compactMap(UUID.init(uuidString:)))
            scopeQuery.includedIDs = candidateIDs.intersection(query.includedIDs ?? candidateIDs)
            let scope = Self.semanticScope(scopeQuery, snippetsOnly: snippetsOnly)
            let fetched = try ClipRow.fetchAll(
                db,
                sql: "SELECT \(ClipRow.metadataSelectionSQL) "
                    + "FROM clip " + scope.sql,
                arguments: StatementArguments(scope.arguments))
            let byID = Dictionary(uniqueKeysWithValues: fetched.map { ($0.id, $0) })
            return topIDs.compactMap { id -> ClipItem? in
                guard let row = byID[id], row.updatedAt == stamps[id] else { return nil }
                return row.item
            }
        }
        try Task.checkCancellation()
        return items
    }

    struct SemanticCandidate: Sendable {
        let id: String
        let score: Float
        let updatedAt: Date
    }

    static func candidatePrecedes(
        _ left: SemanticCandidate, _ right: SemanticCandidate
    ) -> Bool {
        left.score == right.score ? left.id < right.id : left.score > right.score
    }

    static func semanticScope(
        _ query: ClipSearchQuery, snippetsOnly: Bool
    ) -> (sql: String, arguments: [any DatabaseValueConvertible]) {
        var restricted = query
        restricted.excludesSensitive = true
        var sql = "WHERE clip.isArchived = 0"
        var arguments: [any DatabaseValueConvertible] = []
        appendFilters(for: restricted, to: &sql, arguments: &arguments)
        let masked = ClipContentKind.allCases.filter(\.prefersMaskedPreview).map(\.rawValue)
            .sorted()
        sql +=
            " AND clip.kind NOT IN ("
            + Array(repeating: "?", count: masked.count).joined(separator: ",") + ")"
        arguments.append(contentsOf: masked)
        if snippetsOnly { sql += " AND clip.isSnippet = 1" }
        return (sql, arguments)
    }

}

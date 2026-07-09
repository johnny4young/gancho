import Accelerate
import Foundation
import NaturalLanguage

/// Sentence-level text embedding boundary. Implementations are NOT required
/// to be thread-safe — callers own serialization (the product wraps the
/// embedder in an actor next to the store).
public protocol TextEmbedding {
    /// Vector width. `NLContextualEmbedding` multilingual models emit 512.
    var dimension: Int { get }
    func vector(for text: String) throws -> [Float]
}

public enum EmbeddingError: Error, Equatable {
    /// Model assets are not on device yet (`requestAssets` downloads them).
    case assetsUnavailable
    /// The text produced no token vectors (empty or unsupported script).
    case noVectors
    /// A vector's width does not match the index's dimension.
    case dimensionMismatch(expected: Int, got: Int)
}

/// `NLContextualEmbedding`-backed sentence embedder: mean-pools the
/// transformer's token vectors into one sentence vector — the standard
/// pooling for retrieval when the model exposes no sentence head.
public final class ContextualSentenceEmbedder: TextEmbedding {
    private let embedding: NLContextualEmbedding

    public var dimension: Int { embedding.dimension }

    /// Nil when the OS has no contextual model for the language.
    public init?(language: NLLanguage = .english) {
        guard let embedding = NLContextualEmbedding(language: language) else { return nil }
        self.embedding = embedding
    }

    /// True once the model assets are on device. Call `requestAssets()`
    /// (async, may download) before first use on a fresh machine.
    public var hasAvailableAssets: Bool { embedding.hasAvailableAssets }

    public func requestAssets() async throws {
        _ = try await embedding.requestAssets()
    }

    public func vector(for text: String) throws -> [Float] {
        guard embedding.hasAvailableAssets else { throw EmbeddingError.assetsUnavailable }
        let result = try embedding.embeddingResult(for: text, language: nil)

        var sum = [Double](repeating: 0, count: dimension)
        var tokenCount = 0
        result.enumerateTokenVectors(in: text.startIndex..<text.endIndex) { vector, _ in
            vDSP.add(sum, vector, result: &sum)
            tokenCount += 1
            return true
        }
        guard tokenCount > 0 else { throw EmbeddingError.noVectors }
        return vDSP.divide(sum, Double(tokenCount)).map(Float.init)
    }
}

/// In-memory cosine index over unit-normalized vectors, flat `[Float]`
/// storage for Accelerate-friendly scans. A linear scan is the RIGHT
/// structure at clip-history scale: 10k × 512 floats is 20 MB and scans in
/// single-digit milliseconds — an ANN structure would add complexity for
/// nothing below ~1M vectors.
public struct EmbeddingIndex: Sendable {
    public let dimension: Int
    private var ids: [UUID] = []
    private var storage: [Float] = []

    public var count: Int { ids.count }

    public init(dimension: Int) {
        self.dimension = dimension
    }

    /// Inserts a vector, normalizing it so search is a pure dot product.
    /// Zero vectors are rejected (`noVectors`) — they would NaN the scores.
    public mutating func insert(id: UUID, vector: [Float]) throws {
        guard vector.count == dimension else {
            throw EmbeddingError.dimensionMismatch(expected: dimension, got: vector.count)
        }
        let norm = sqrt(vDSP.sumOfSquares(vector))
        guard norm > 0 else { throw EmbeddingError.noVectors }
        ids.append(id)
        storage.append(contentsOf: vDSP.divide(vector, norm))
    }

    /// Exact cosine top-K via one vectorized dot product per row.
    public func search(_ query: [Float], topK: Int) throws -> [(id: UUID, score: Float)] {
        guard query.count == dimension else {
            throw EmbeddingError.dimensionMismatch(expected: dimension, got: query.count)
        }
        guard !ids.isEmpty, topK > 0 else { return [] }
        let norm = sqrt(vDSP.sumOfSquares(query))
        guard norm > 0 else { throw EmbeddingError.noVectors }
        let unit = vDSP.divide(query, norm)

        var scores = [Float](repeating: 0, count: ids.count)
        storage.withUnsafeBufferPointer { flat in
            unit.withUnsafeBufferPointer { q in
                for row in 0..<ids.count {
                    var dot: Float = 0
                    vDSP_dotpr(
                        flat.baseAddress! + row * dimension, 1,
                        q.baseAddress!, 1, &dot, vDSP_Length(dimension))
                    scores[row] = dot
                }
            }
        }

        return
            zip(ids, scores)
            .sorted { $0.1 > $1.1 }
            .prefix(topK)
            .map { (id: $0.0, score: $0.1) }
    }
}

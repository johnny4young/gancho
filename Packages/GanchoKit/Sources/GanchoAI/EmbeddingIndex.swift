import Accelerate
import Foundation
import GanchoKit
import NaturalLanguage
import Synchronization

/// Sentence-level text embedding boundary. Implementations are NOT required
/// to be thread-safe; `SharedSentenceEmbedder` serializes the product's calls.
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

    /// Frees the model; the next `vector(for:)` loads it again.
    public func unload() {
        embedding.unload()
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

/// An embedder whose model can be freed and reloaded on demand.
protocol ReloadableTextEmbedding: TextEmbedding {
    var hasAvailableAssets: Bool { get }
    func unload()
}

extension ContextualSentenceEmbedder: ReloadableTextEmbedding {}

/// The process-wide contextual embedder. Building an `NLContextualEmbedding`
/// loads its tokenizer and weights, which costs several times one embedding, so
/// capture, search, board suggestions and the refresh pass share this one. Calls
/// are serialized, and the model unloads after `idleUnload` without use.
public final class SharedSentenceEmbedder: TextEmbedding, Sendable {
    public static let shared = SharedSentenceEmbedder()

    private struct State {
        var embedder: (any ReloadableTextEmbedding)?
        var lastUse = ContinuousClock.now
        var isLoaded = false
        var unloadArmed = false
    }

    private let state = Mutex(State())
    private let idleUnload: Duration
    private let makeEmbedder: @Sendable () -> (any ReloadableTextEmbedding)?

    init(
        idleUnload: Duration = .seconds(180),
        makeEmbedder: @escaping @Sendable () -> (any ReloadableTextEmbedding)? = {
            ContextualSentenceEmbedder()
        }
    ) {
        self.idleUnload = idleUnload
        self.makeEmbedder = makeEmbedder
    }

    /// This embedder when the model assets are on device, else nil.
    public var ifAvailable: SharedSentenceEmbedder? {
        hasAvailableAssets ? self : nil
    }

    public var hasAvailableAssets: Bool {
        state.withLock { resolved(&$0)?.hasAvailableAssets ?? false }
    }

    public var dimension: Int {
        state.withLock { resolved(&$0)?.dimension ?? 0 }
    }

    public func vector(for text: String) throws -> [Float] {
        let vector = try state.withLock { state throws -> [Float] in
            guard let embedder = resolved(&state) else { throw EmbeddingError.assetsUnavailable }
            state.lastUse = .now
            state.isLoaded = true
            return try embedder.vector(for: text)
        }
        armIdleUnload()
        return vector
    }

    private func resolved(_ state: inout State) -> (any ReloadableTextEmbedding)? {
        if state.embedder == nil { state.embedder = makeEmbedder() }
        return state.embedder
    }

    private func armIdleUnload() {
        let shouldArm = state.withLock { state in
            guard !state.unloadArmed else { return false }
            state.unloadArmed = true
            return true
        }
        guard shouldArm else { return }
        Task.detached(priority: .background) { [self] in await unloadWhenIdle() }
    }

    private func unloadWhenIdle() async {
        var wait = idleUnload
        while true {
            try? await Task.sleep(for: wait, tolerance: idleUnload / 10)
            let remaining = state.withLock { state -> Duration in
                let idle = ContinuousClock.now - state.lastUse
                guard idle >= idleUnload else { return idleUnload - idle }
                if state.isLoaded { state.embedder?.unload() }
                state.isLoaded = false
                state.unloadArmed = false
                return .zero
            }
            if remaining == .zero { return }
            wait = remaining
        }
    }
}

/// In-memory cosine index over unit-normalized vectors, flat `[Float]`
/// storage for Accelerate-friendly scans. A linear scan is the RIGHT
/// structure at clip-history scale: 10k × 512 floats is 20 MB and scans in
/// single-digit milliseconds (measured p95 3.8 ms in a release build; an
/// unoptimized test build is roughly 7x that, so read benchmark output with
/// the build in mind) — an ANN structure would add complexity for nothing
/// below ~1M vectors.
///
/// That trade-off rests on the scan staying exact, which is what the tests
/// hold it to: `EmbeddingIndexTests` proves the top-K is the true top-K
/// regardless of machine speed, and `EmbeddingIndexPerformanceTests`
/// (`GANCHO_PERF=1 make bench`) tracks the wall-clock p95 and the slope.
public struct EmbeddingIndex: Sendable {
    public let dimension: Int
    private var ids: [UUID] = []
    private var storage: [Float] = []

    public var count: Int { ids.count }

    public init(dimension: Int) {
        self.dimension = dimension
    }

    /// Inserts a vector, normalizing it so search is a pure dot product.
    /// Zero, non-finite, and overflowing norms are rejected (`noVectors`).
    public mutating func insert(id: UUID, vector: [Float]) throws {
        guard vector.count == dimension else {
            throw EmbeddingError.dimensionMismatch(expected: dimension, got: vector.count)
        }
        let norm = sqrt(vDSP.sumOfSquares(vector))
        guard norm > 0, norm.isFinite else { throw EmbeddingError.noVectors }
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
        guard norm > 0, norm.isFinite else { throw EmbeddingError.noVectors }
        let unit = vDSP.divide(query, norm)

        var top = BoundedTopK<(row: Int, score: Float)>(limit: topK) {
            $0.score == $1.score ? $0.row < $1.row : $0.score > $1.score
        }
        storage.withUnsafeBufferPointer { flat in
            unit.withUnsafeBufferPointer { q in
                for row in 0..<ids.count {
                    var dot: Float = 0
                    vDSP_dotpr(
                        flat.baseAddress! + row * dimension, 1,
                        q.baseAddress!, 1, &dot, vDSP_Length(dimension))
                    top.insert((row, dot))
                }
            }
        }

        return top.sorted.map { (id: ids[$0.row], score: $0.score) }
    }
}

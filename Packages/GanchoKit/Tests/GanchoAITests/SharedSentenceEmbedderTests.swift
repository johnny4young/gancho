import Foundation
import Synchronization
import Testing

@testable import GanchoAI

@Suite("Shared sentence embedder")
struct SharedSentenceEmbedderTests {
    @Test("Every call reuses one model")
    func reusesOneModel() throws {
        let probe = ModelProbe()
        let shared = SharedSentenceEmbedder(makeEmbedder: { probe.make() })

        for index in 0..<5 {
            _ = try #require(shared.ifAvailable).vector(for: "clip \(index)")
        }

        #expect(probe.created.withLock { $0 } == 1)
        #expect(probe.vectors.withLock { $0 } == 5)
    }

    @Test("Missing assets yield no embedder")
    func missingAssets() {
        let probe = ModelProbe(hasAssets: false)
        let shared = SharedSentenceEmbedder(makeEmbedder: { probe.make() })

        #expect(shared.ifAvailable == nil)
        #expect(throws: EmbeddingError.assetsUnavailable) {
            _ = try SharedSentenceEmbedder(makeEmbedder: { nil }).vector(for: "text")
        }
    }

    @Test("A language without a model is retried on the next call")
    func retriesConstruction() throws {
        let attempts = Mutex(0)
        let probe = ModelProbe()
        let shared = SharedSentenceEmbedder(makeEmbedder: {
            attempts.withLock { $0 += 1 }
            return attempts.withLock { $0 } == 1 ? nil : probe.make()
        })

        #expect(shared.ifAvailable == nil)
        _ = try #require(shared.ifAvailable).vector(for: "text")
        #expect(attempts.withLock { $0 } == 2)
    }

    @Test("The model unloads once idle and reloads on the next call")
    func unloadsWhenIdle() async throws {
        let probe = ModelProbe()
        let shared = SharedSentenceEmbedder(
            idleUnload: .milliseconds(50), makeEmbedder: { probe.make() })

        _ = try shared.vector(for: "first")
        try await waitUntil { probe.unloads.withLock { $0 } == 1 }

        _ = try shared.vector(for: "second")
        try await waitUntil { probe.unloads.withLock { $0 } == 2 }
        #expect(probe.created.withLock { $0 } == 1)
    }

    @Test("Concurrent callers never run the model at the same time")
    func serializesCalls() async throws {
        let probe = ModelProbe()
        let shared = SharedSentenceEmbedder(makeEmbedder: { probe.make() })

        await withTaskGroup(of: Void.self) { group in
            for index in 0..<16 {
                group.addTask { _ = try? shared.vector(for: "clip \(index)") }
            }
        }

        #expect(probe.maxConcurrent.withLock { $0 } == 1)
        #expect(probe.vectors.withLock { $0 } == 16)
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = ContinuousClock.now + .seconds(5)
        while !condition() {
            guard ContinuousClock.now < deadline else {
                Issue.record("Condition not met within 5 s")
                return
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }
}

private final class ModelProbe: Sendable {
    let created = Mutex(0)
    let vectors = Mutex(0)
    let unloads = Mutex(0)
    let maxConcurrent = Mutex(0)
    let running = Mutex(0)
    let hasAssets: Bool

    init(hasAssets: Bool = true) {
        self.hasAssets = hasAssets
    }

    func make() -> any ReloadableTextEmbedding {
        created.withLock { $0 += 1 }
        return ProbeEmbedder(probe: self)
    }
}

private struct ProbeEmbedder: ReloadableTextEmbedding {
    let probe: ModelProbe
    var dimension: Int { 4 }
    var hasAvailableAssets: Bool { probe.hasAssets }

    func vector(for text: String) throws -> [Float] {
        let now = probe.running.withLock { running in
            running += 1
            return running
        }
        probe.maxConcurrent.withLock { $0 = max($0, now) }
        Thread.sleep(forTimeInterval: 0.002)
        probe.running.withLock { $0 -= 1 }
        probe.vectors.withLock { $0 += 1 }
        return [1, 0, 0, 0]
    }

    func unload() {
        probe.unloads.withLock { $0 += 1 }
    }
}

import Foundation
import GanchoKit
import Testing

@testable import GanchoAI

/// Wall-clock budgets for the on-device intelligence path — opt-in
/// (`GANCHO_PERF=1 make bench`), alongside the storage harness in
/// `GanchoKitTests/PerformanceHarnessTests.swift`.
///
/// These do NOT belong in the default suite. Timing is a property of the
/// machine as much as of the code, and `make test` runs from the pre-push
/// hook while builds are still settling: a budget tight enough to detect a
/// regression there fails pushes of unrelated work, and one loose enough to
/// survive arbitrary load detects nothing. The load-independent properties
/// these numbers used to stand in for are asserted in the always-on suites —
/// exact top-K ranking in `EmbeddingIndexTests`, the 55 classification cases
/// in `RuleClassifierSuiteTests`.
///
/// Budgets here are CEILINGS for serious regressions, not targets; the trend
/// lines print either way so drift stays visible in the job summary.
enum AIPerf {
    /// True only on GitHub's shared hosted runners.
    ///
    /// Same contract as the storage harness: `perf.yml` derives this from
    /// `runner.environment`, NOT from `CI`. See the rationale on
    /// `PerformanceHarnessTests.isHostedRunner` — in short, `CI` is set by
    /// every CI system and by anyone who exports it, says nothing about
    /// whether the hardware is shared, and is commonly the literal `false`.
    /// Absent or anything but `true` means dedicated hardware, which keeps
    /// the strict budget.
    static var isHostedRunner: Bool {
        ProcessInfo.processInfo.environment["GANCHO_PERF_HOSTED_RUNNER"] == "true"
    }

    /// Shared, thermally-throttled hardware: the smallest change separable
    /// from runner noise is roughly a doubling, so that is the relaxation.
    static func budget(_ strict: Duration) -> Duration {
        isHostedRunner ? strict * 2 : strict
    }

    /// `Duration.components` splits whole seconds from the attosecond
    /// remainder, so a ratio taken over `attoseconds` alone silently drops
    /// everything past one second. Fold both halves before dividing.
    static func seconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) + Double(components.attoseconds) / 1e18
    }

    static func summarize(_ samples: [Duration]) -> (median: Duration, p95: Duration, max: Duration)
    {
        precondition(!samples.isEmpty)
        let sorted = samples.sorted()
        return (
            sorted[sorted.count / 2],
            sorted[Int(0.95 * Double(sorted.count - 1))],
            sorted[sorted.count - 1]
        )
    }
}

@Suite(
    "EmbeddingIndex performance — exact cosine at clip-history scale",
    .enabled(if: ProcessInfo.processInfo.environment["GANCHO_PERF"] == "1"),
    .serialized)
struct EmbeddingIndexPerformanceTests {
    static let scale = 10_000
    static let dimension = 512
    static let rounds = 20
    /// Ceiling for the scan on a quiet machine, calibrated to the build
    /// `make bench` actually runs: DEBUG, where the scan measures ~26 ms. The
    /// same code in a release build measures ~3.8 ms, so this number is a
    /// regression tripwire for the harness, NOT a claim about product latency
    /// — `EmbeddingIndex`'s own doc comment carries the shipped figure.
    static let searchP95Budget = Duration.milliseconds(60)

    @Test("Top-K over 10k×512 holds the search p95 budget")
    func searchP95() throws {
        var index = EmbeddingIndex(dimension: Self.dimension)
        for seed in 0..<Self.scale {
            try index.insert(
                id: UUID(),
                vector: SyntheticVectors.vector(seed: seed, dimension: Self.dimension))
        }
        let query = SyntheticVectors.vector(seed: 4242, dimension: Self.dimension)
        let budget = AIPerf.budget(Self.searchP95Budget)
        print(
            "perf: embedding method environment=\(AIPerf.isHostedRunner ? "github-hosted" : "dedicated") "
                + "scale=\(Self.scale)x\(Self.dimension) warmup=1 rounds=\(Self.rounds) "
                + "p95-budget=\(budget) p95-budget-strict=\(Self.searchP95Budget)")

        // One untimed warmup separates first-touch page faults over the 20 MB
        // backing store from the steady-state number the budget is about.
        _ = try index.search(query, topK: 10)

        var latencies: [Duration] = []
        for _ in 0..<Self.rounds {
            let start = ContinuousClock.now
            let hits = try index.search(query, topK: 10)
            latencies.append(ContinuousClock.now - start)
            #expect(hits.count == 10)
        }
        let summary = AIPerf.summarize(latencies)
        print(
            "perf: embedding search over \(Self.scale)x\(Self.dimension): "
                + "median=\(summary.median) p95=\(summary.p95) max=\(summary.max)")
        #expect(summary.p95 < budget, "search p95 \(summary.p95) blew the \(budget) budget")
    }

    /// Cost must stay linear in the number of vectors — that is the whole
    /// claim behind choosing a flat scan over an ANN structure. Doubling the
    /// corpus may not more than triple the work; the slack absorbs cache
    /// effects without accepting a quadratic scan.
    @Test("Search cost grows linearly with the corpus")
    func searchScalesLinearly() throws {
        func p95(vectors: Int) throws -> Duration {
            var index = EmbeddingIndex(dimension: Self.dimension)
            for seed in 0..<vectors {
                try index.insert(
                    id: UUID(),
                    vector: SyntheticVectors.vector(seed: seed, dimension: Self.dimension))
            }
            let query = SyntheticVectors.vector(seed: 4242, dimension: Self.dimension)
            _ = try index.search(query, topK: 10)
            var latencies: [Duration] = []
            for _ in 0..<Self.rounds {
                let start = ContinuousClock.now
                _ = try index.search(query, topK: 10)
                latencies.append(ContinuousClock.now - start)
            }
            return AIPerf.summarize(latencies).p95
        }

        let small = try p95(vectors: Self.scale / 2)
        let large = try p95(vectors: Self.scale)
        let ratio = AIPerf.seconds(large) / AIPerf.seconds(small)
        print(
            "perf: embedding scaling \(Self.scale / 2)->\(Self.scale): "
                + "p95 \(small)->\(large) ratio=\(String(format: "%.2f", ratio))")
        #expect(ratio < 3, "doubling the corpus multiplied search cost by \(ratio)")
    }
}

@Suite(
    "RuleClassifier performance — the tier-0 ingest budget",
    .enabled(if: ProcessInfo.processInfo.environment["GANCHO_PERF"] == "1"),
    .serialized)
struct RuleClassifierPerformanceTests {
    static let rounds = 20
    /// The `<5 ms` figure the classifier's own doc comment promises, for the
    /// clip-sized inputs the case suite covers.
    static let classifyP95Budget = Duration.milliseconds(5)

    @Test("Classification holds the 5ms p95 budget over the case suite")
    func classifyP95() {
        let classifier = RuleClassifier()
        let inputs = RuleClassifierSuiteTests.cases.map(\.0)
        for input in inputs { _ = classifier.classify(input) }  // untimed warmup

        var latencies: [Duration] = []
        for _ in 0..<Self.rounds {
            for input in inputs {
                let start = ContinuousClock.now
                _ = classifier.classify(input)
                latencies.append(ContinuousClock.now - start)
            }
        }
        let summary = AIPerf.summarize(latencies)
        let budget = AIPerf.budget(Self.classifyP95Budget)
        print(
            "perf: classify over \(inputs.count) cases x \(Self.rounds) rounds: "
                + "n=\(latencies.count) median=\(summary.median) p95=\(summary.p95) "
                + "max=\(summary.max) p95-budget=\(budget)")
        #expect(summary.p95 < budget, "classify p95 \(summary.p95) blew the \(budget) budget")
    }

    /// Every detector reads the WHOLE string (the data-detector kinds require
    /// a full-range match), so cost is linear in length — a megabyte paste is
    /// not a 5 ms call. This records that slope rather than pretending the
    /// clip-sized budget covers it, and fails if it turns superlinear.
    @Test("Classification cost stays linear in input length")
    func classifyScalesLinearly() {
        let classifier = RuleClassifier()
        func median(chars: Int) -> Duration {
            let unit = "lorem ipsum dolor "
            let text = String(repeating: unit, count: max(1, chars / unit.count))
            _ = classifier.classify(text)
            var latencies: [Duration] = []
            for _ in 0..<5 {
                let start = ContinuousClock.now
                _ = classifier.classify(text)
                latencies.append(ContinuousClock.now - start)
            }
            return AIPerf.summarize(latencies).median
        }

        let small = median(chars: 50_000)
        let large = median(chars: 200_000)
        let ratio = AIPerf.seconds(large) / AIPerf.seconds(small)
        print(
            "perf: classify scaling 50k->200k chars: \(small)->\(large) "
                + "ratio=\(String(format: "%.2f", ratio)) (linear would be ~4)")
        #expect(ratio < 8, "quadrupling the input multiplied classify cost by \(ratio)")
    }
}

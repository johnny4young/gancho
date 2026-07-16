import Foundation
import GRDB
import Testing

@_spi(GanchoInternal) @testable import GanchoKit

/// Deterministic synthetic clip fixtures with a realistic shape. NEVER real
/// clipboard content — distribution and sizes are what matter for perf.
enum ClipFixtures {
    /// Splittable LCG so fixture generation is reproducible run to run.
    struct Generator {
        private var state: UInt64
        init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 | 1 }
        mutating func next(_ bound: Int) -> Int {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            return Int(truncatingIfNeeded: (state >> 33) % UInt64(bound))
        }
    }

    static let words = [
        "meeting", "deploy", "invoice", "ticket", "review", "draft", "agenda",
        "release", "branch", "staging", "credentials", "rotate", "quarterly",
        "dentist", "groceries", "flight", "tracking", "snippet", "shortcut"
    ]

    /// Realistic mix: mostly text of varied length, some URLs/code/JSON,
    /// a sprinkle of pins, sensitivity, and expiry.
    static func make(count: Int, seed: UInt64 = 42) -> [(item: ClipItem, content: ClipContent?)] {
        var generator = Generator(seed: seed)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        return (0..<count).map { index in
            let roll = generator.next(100)
            let kind: ClipContentKind
            let text: String
            switch roll {
            case 0..<70:
                kind = .text
                let length = 3 + generator.next(40)
                text =
                    (0..<length).map { _ in words[generator.next(words.count)] }
                    .joined(separator: " ") + " #\(index)"
            case 70..<82:
                kind = .url
                text =
                    "https://example.com/\(words[generator.next(words.count)])/\(index)?page=\(generator.next(9))"
            case 82..<92:
                kind = .code
                text = "func handle\(index)() { return \(generator.next(1000)) }"
            default:
                kind = .json
                text = "{\"id\": \(index), \"name\": \"\(words[generator.next(words.count)])\"}"
            }
            let item = ClipItem(
                createdAt: base.addingTimeInterval(Double(index)),
                lastUsedAt: base.addingTimeInterval(Double(index)),
                kind: kind,
                preview: String(text.prefix(120)),
                contentHash: "fixture-\(index)",
                sourceAppBundleID: "com.example.app\(generator.next(8))",
                isPinned: generator.next(100) < 5,
                isSensitive: generator.next(100) < 3,
                expiresAt: generator.next(100) < 10
                    ? base.addingTimeInterval(Double(index) + 86_400) : nil
            )
            return (item, .text(text))
        }
    }
}

/// Scale benchmarks — opt-in (`GANCHO_PERF=1 make bench`): seeding 100k rows
/// takes seconds, which does not belong in the PR loop. Budgets are CEILINGS
/// for serious regressions, not targets; trends print to the log/summary.
@Suite(
    "Performance harness — budgets at scale",
    .enabled(if: ProcessInfo.processInfo.environment["GANCHO_PERF"] == "1"),
    .serialized)
struct PerformanceHarnessTests {
    static let scale = 100_000
    static let searchRounds = 5
    static let coldSearchBudget = Duration.milliseconds(150)
    static let warmSearchP95Budget = Duration.milliseconds(50)
    static let searchQueries = [
        "deploy", "quarterly inv", "dent", "stag", "rotate cred", "tick",
        "release bran", "flight track", "agen", "snip short", "meeting",
        "func handle", "example", "groc", "draft rev", "invoice quart",
        "branch stag", "credentials", "review", "json name"
    ]

    private struct LatencySummary {
        let median: Duration
        let p95: Duration
        let maximum: Duration

        init(_ samples: [Duration]) {
            precondition(!samples.isEmpty)
            let sorted = samples.sorted()
            median = sorted[sorted.count / 2]
            p95 = sorted[Int(0.95 * Double(sorted.count - 1))]
            maximum = sorted[sorted.count - 1]
        }
    }

    private func makeSeededStore(upTo migration: String? = nil) async throws -> GRDBClipboardStore {
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("perf-\(UUID().uuidString)")))
        if let migration {
            try store.migrate(upTo: migration)
        } else {
            try store.migrate()
        }
        let fixtures = ClipFixtures.make(count: Self.scale)
        let start = ContinuousClock.now
        if migration != nil {
            // Partial-schema seeding: `importBatch` writes the full current
            // `ClipRow` (isArchived v5, sync fields v8, keyword/uses v13…),
            // which a v1-only table rejects — so seed with an INSERT that names
            // v1 columns only. Test-side on purpose: production never inserts
            // into a half-migrated store.
            try await seedAtV1(store, fixtures: fixtures)
        } else {
            try await store.importBatch(fixtures)
        }
        print("perf: seeded \(Self.scale) clips in \(ContinuousClock.now - start)")
        return store
    }

    /// Bulk insert naming ONLY the v1 columns. `ClipRow` does the field mapping
    /// (kind rawValue, tags JSON) so the stored format matches production; the
    /// raw SQL just narrows the column list to what the v1 schema has.
    private func seedAtV1(
        _ store: GRDBClipboardStore,
        fixtures: [(item: ClipItem, content: ClipContent?)]
    ) async throws {
        try await store.writer.write { db in
            for entry in fixtures {
                var row = ClipRow(item: entry.item)
                if case .text(let text)? = entry.content { row.contentText = text }
                try db.execute(
                    sql: """
                        INSERT INTO clip
                          (id, createdAt, updatedAt, lastUsedAt, kind, title, preview,
                           contentHash, sourceAppBundleID, sourceDeviceName, isPinned,
                           isSensitive, expiresAt, tags, contentText)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        row.id, row.createdAt, row.updatedAt, row.lastUsedAt, row.kind,
                        row.title, row.preview, row.contentHash, row.sourceAppBundleID,
                        row.sourceDeviceName, row.isPinned, row.isSensitive,
                        row.expiresAt, row.tags, row.contentText
                    ])
            }
        }
    }

    /// Deterministically varies query order so one favorable sequence cannot
    /// hide cache-sensitive regressions, while keeping hosted runs comparable.
    private func searchQueries(forRound round: Int) -> [String] {
        var queries = Self.searchQueries
        var generator = ClipFixtures.Generator(seed: UInt64(round + 1))
        for index in stride(from: queries.count - 1, through: 1, by: -1) {
            queries.swapAt(index, generator.next(index + 1))
        }
        return queries
    }

    /// Test-only fault injection proves the gate still fails when every query
    /// is deliberately slowed; normal and hosted runs leave the variable unset.
    private var injectedSearchDelay: Duration {
        let raw = ProcessInfo.processInfo.environment["GANCHO_PERF_SEARCH_DELAY_MS"]
        guard let raw, let milliseconds = Int64(raw), milliseconds > 0 else { return .zero }
        return .milliseconds(milliseconds)
    }

    private func measureSearch(
        _ query: String,
        store: GRDBClipboardStore
    ) async throws -> Duration {
        let start = ContinuousClock.now
        _ = try await store.search(ClipSearchQuery(text: query), limit: 50)
        if injectedSearchDelay > .zero {
            try await Task.sleep(for: injectedSearchDelay)
        }
        return ContinuousClock.now - start
    }

    @Test("Board page reads stay interactive over a 10k-member board")
    func boardPageBudget() async throws {
        let boardScale = 10_000
        let pageBudget = Duration.milliseconds(100)
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(),
            blobs: BlobStore(
                directory: FileManager.default.temporaryDirectory
                    .appendingPathComponent("perf-board-\(UUID().uuidString)")))
        try store.migrate()
        let fixtures = ClipFixtures.make(count: boardScale)
        try await store.importBatch(fixtures)
        let board = try await store.createPinboard(name: "Everything")
        let seedStart = ContinuousClock.now
        try await store.setBoardMembership(
            clipIDs: fixtures.map(\.item.id), boardID: board.id, member: true)
        print("perf: board membership seeded \(boardScale) in \(ContinuousClock.now - seedStart)")

        // The page a user sees on opening the board — the interactive path.
        let firstStart = ContinuousClock.now
        let firstPage = try await store.items(inBoard: board.id, limit: 100)
        let firstCost = ContinuousClock.now - firstStart
        #expect(firstPage.count == 100)
        print("perf: board first page over \(boardScale) members: \(firstCost)")
        #expect(firstCost < pageBudget)

        // A deep page (the worst OFFSET) must not degrade past the same budget.
        let deepStart = ContinuousClock.now
        let deepPage = try await store.items(
            inBoard: board.id, offset: boardScale - 50, limit: 100)
        let deepCost = ContinuousClock.now - deepStart
        #expect(deepPage.count == 50)
        print("perf: board deep page (offset \(boardScale - 50)): \(deepCost)")
        #expect(deepCost < pageBudget)
    }

    @Test("FTS5 cold and warm search budgets hold over 100k clips")
    func searchBudget() async throws {
        let store = try await makeSeededStore()
        let environment = ProcessInfo.processInfo.environment["CI"] == nil ? "local" : "hosted-ci"
        print(
            "perf: FTS5 method environment=\(environment) cold=1 warmup=1 "
                + "warm-rounds=\(Self.searchRounds) queries-per-round=\(Self.searchQueries.count) "
                + "cold-budget=\(Self.coldSearchBudget) "
                + "warm-p95-budget=\(Self.warmSearchP95Budget)")
        let cold = try await measureSearch("quarterly inv", store: store)
        print("perf: FTS5 cold first query over \(Self.scale): \(cold)")

        // One explicit untimed warmup separates launch/cache cost from the
        // interactive budget rather than silently mixing both populations.
        _ = try await store.search(ClipSearchQuery(text: "deploy"), limit: 50)

        var warmLatencies: [Duration] = []
        for round in 1...Self.searchRounds {
            var roundLatencies: [Duration] = []
            for query in searchQueries(forRound: round) {
                roundLatencies.append(try await measureSearch(query, store: store))
            }
            warmLatencies += roundLatencies
            let summary = LatencySummary(roundLatencies)
            print(
                "perf: FTS5 warm round \(round)/\(Self.searchRounds) over \(Self.scale): "
                    + "median=\(summary.median) p95=\(summary.p95) max=\(summary.maximum)")
        }
        let warm = LatencySummary(warmLatencies)
        print(
            "perf: FTS5 warm aggregate over \(Self.scale): "
                + "n=\(warmLatencies.count) median=\(warm.median) "
                + "p95=\(warm.p95) max=\(warm.maximum)")

        #expect(
            cold < Self.coldSearchBudget,
            "cold query \(cold) blew the \(Self.coldSearchBudget) budget")
        #expect(
            warm.p95 < Self.warmSearchP95Budget,
            "warm p95 \(warm.p95) blew the \(Self.warmSearchP95Budget) budget")
    }

    @Test("FTS index build over 100k existing rows stays under 10s")
    func migrationBudget() async throws {
        // Populate at v1 (no FTS), then measure what v2 costs on real data.
        let store = try await makeSeededStore(upTo: "v1-clips")
        let start = ContinuousClock.now
        try store.migrate()
        let elapsed = ContinuousClock.now - start
        print("perf: v2 FTS build over \(Self.scale) rows: \(elapsed)")
        #expect(elapsed < .seconds(10), "FTS migration \(elapsed) blew the 10s budget")
        // Sanity: the freshly built index actually answers.
        #expect(try await !store.search(ClipSearchQuery(text: "deploy")).isEmpty)
    }

    @Test("Cold paging through 100k rows stays under the boot budget")
    func bootPagingBudget() async throws {
        let store = try await makeSeededStore()
        let start = ContinuousClock.now
        let firstPage = try await store.items(offset: 0, limit: 100)
        let elapsed = ContinuousClock.now - start
        print("perf: first page over \(Self.scale): \(elapsed)")
        #expect(firstPage.count == 100)
        #expect(elapsed < .seconds(1), "first page \(elapsed) blew the 1s boot budget")
    }

    @Test("Purge of half the rows + vacuum stays under 5s")
    func purgeVacuumBudget() async throws {
        let store = try await makeSeededStore()
        let start = ContinuousClock.now
        let purged = try await store.purgeForTest(olderThan: 1_700_050_000)
        try await store.vacuum()
        let elapsed = ContinuousClock.now - start
        print("perf: purged \(purged) rows + vacuum: \(elapsed)")
        #expect(purged > 0)
        #expect(elapsed < .seconds(5), "purge+vacuum \(elapsed) blew the 5s budget")
    }
}

extension GRDBClipboardStore {
    /// Raw date-cutoff purge for the perf harness; the retention engine owns
    /// the real policy-driven purge.
    func purgeForTest(olderThan epoch: TimeInterval) async throws -> Int {
        try await writer.write { db in
            try db.execute(
                sql: "DELETE FROM clip WHERE createdAt < ?",
                arguments: [Date(timeIntervalSince1970: epoch)])
            return db.changesCount
        }
    }
}

@Suite("Storage structure — list paths never touch blobs")
struct ListBlobIsolationTests {
    @Test("Paging works even when blob files are gone (lists read no blobs)")
    func listsNeverReadBlobs() async throws {
        let blobDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("isolation-\(UUID().uuidString)")
        let store = GRDBClipboardStore(
            writer: try DatabaseQueue(), blobs: BlobStore(directory: blobDir))
        try store.migrate()

        let png = Data(
            base64Encoded:
                "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg=="
        )!
        let item = ClipItem(kind: .image, preview: "Image", contentHash: "img")
        try await store.insert(item, content: .binary(data: png, typeIdentifier: "public.png"))

        // Nuke the blob storage entirely: if listing touched blobs, this
        // would surface. It must not — lists are metadata-only by contract.
        try FileManager.default.removeItem(at: blobDir)
        let items = try await store.items()
        #expect(items.count == 1)
        // Content fetch is the only blob-loading path, and it degrades to nil.
        #expect(try await store.content(for: item.id) == nil)
    }
}

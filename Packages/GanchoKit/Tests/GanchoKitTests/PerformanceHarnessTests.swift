import Accelerate
import Darwin
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
    /// Interactive ceiling on a quiet machine.
    static let warmSearchP95Budget = Duration.milliseconds(50)

    /// True only on GitHub's shared hosted runners, where wall-clock latency is
    /// not ours alone.
    ///
    /// Deliberately NOT keyed on `CI`. That variable is set by every CI system
    /// and by anyone who exports it, it says nothing about whether the hardware
    /// is shared, and it is commonly set to the literal `false` — which a
    /// presence check would read as hosted. `perf.yml` derives this flag from
    /// `runner.environment` instead, so the relaxed budget reaches exactly the
    /// shared runners it was measured on: a self-hosted runner is dedicated
    /// hardware and keeps the strict budget, as does every local run.
    ///
    /// Absent or anything but `true` means dedicated. The strict budget is the
    /// safe default: the worst case is a noise-driven failure someone
    /// investigates, not a regression that ships unnoticed.
    static var isHostedRunner: Bool {
        ProcessInfo.processInfo.environment["GANCHO_PERF_HOSTED_RUNNER"] == "true"
    }

    /// The warm ceiling actually enforced.
    ///
    /// A hosted macOS runner is a shared, thermally-throttled VM: the run that
    /// failed this gate measured a p95 of 53 ms with a MEDIAN of 38 ms, and
    /// per-round p95s spanning 46–60 ms. That spread is the runner, not the
    /// query — a 50 ms line sits inside its normal variance, so the gate was
    /// reporting noise as a regression.
    ///
    /// Doubling it on hosted runs keeps the ceiling meaningful: these budgets
    /// are declared CEILINGS for serious regressions, and on hardware we do not
    /// control the smallest change we can distinguish from noise is roughly a
    /// doubling. The per-round trend lines still print either way, so gradual
    /// drift stays visible in the job summary even though it does not fail the
    /// build. Dedicated hardware — a developer's Mac or a self-hosted runner —
    /// keeps the real 50 ms interactive budget.
    static var effectiveWarmSearchP95Budget: Duration {
        isHostedRunner ? warmSearchP95Budget * 2 : warmSearchP95Budget
    }

    /// Ceiling for a cold upgrade launch that rebuilds the FTS index over 100k
    /// rows in an encrypted on-disk store.
    ///
    /// Measured baseline: 1.2 s on an Apple-silicon Mac. Ten seconds leaves
    /// roughly eight times that locally and three to four on a hosted runner —
    /// wide enough that machine-to-machine spread never flaps it, tight enough
    /// that a migration which makes launch take a minute cannot pass. This
    /// number is a single sample of one long operation, not a p95 of many short
    /// ones, so it needs no hosted-runner allowance the way the search gate
    /// does.
    static let launchOpenBudget = Duration.seconds(10)

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

    // MARK: - Semantic retrieval at scale

    /// Seeds `count` synthetic 512-d embeddings behind real clip rows in ONE
    /// write transaction — per-row `saveEmbedding` round-trips would dominate
    /// the seeding, not the measurement. Vectors come from the seeded LCG so
    /// runs are reproducible; the store is in-memory like the FTS harness, so
    /// the phase numbers are a relative breakdown, not disk latencies.
    private func seedEmbeddings(into store: GRDBClipboardStore, count: Int) async throws {
        let fixtures = ClipFixtures.make(count: count)
        try await store.importBatch(fixtures)
        try await store.writer.write { db in
            var generator = ClipFixtures.Generator(seed: 7)
            for entry in fixtures {
                var vector = [Float](repeating: 0, count: 512)
                for lane in 0..<512 {
                    vector[lane] = Float(generator.next(2_000)) / 1_000 - 1
                }
                let data = vector.withUnsafeBufferPointer { Data(buffer: $0) }
                try db.execute(
                    sql: """
                        INSERT OR REPLACE INTO clip_embedding
                          (clipID, dimension, vector, modelVersion)
                        VALUES (?, ?, ?, ?)
                        """,
                    arguments: [
                        entry.item.id.uuidString, 512, data,
                        EmbeddingModelInfo.currentVersion
                    ])
            }
        }
    }

    private func queryVector() -> [Float] {
        var generator = ClipFixtures.Generator(seed: 99)
        return (0..<512).map { _ in Float(generator.next(2_000)) / 1_000 - 1 }
    }

    /// Current process physical footprint — the "bounded memory" evidence.
    private func residentFootprint() -> Int {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? Int(info.phys_footprint) : 0
    }

    /// The exact-linear-search phases, measured SEPARATELY over the same rows
    /// the production query reads (same SQL, same filters): raw row fetch,
    /// Data→[Float] conversion, norm calculation, vectorized scoring, then full
    /// sort vs bounded partial top-K selection. The breakdown is the evidence
    /// for (or against) caching a normalized matrix or changing the selection.
    ///
    /// It models the MATERIALIZED shape — fetch everything, convert, then score
    /// — which is no longer how `semanticSearch` works: production streams a
    /// cursor and scores each vector where its bytes already are. So these
    /// phases still say where the work is in a linear scan, but the sum of them
    /// is NOT the production latency, and `db-fetch` in particular measures a
    /// materialization production no longer performs. Read the end-to-end line
    /// for what the query actually costs.
    private func measurePhases(
        store: GRDBClipboardStore, query: [Float], topK: Int
    ) async throws -> [(String, Duration)] {
        var phases: [(String, Duration)] = []
        let clock = ContinuousClock()

        var start = clock.now
        let rows = try await store.writer.read { db in
            try Row.fetchAll(
                db,
                sql: """
                    SELECT e.clipID, e.vector FROM clip_embedding e
                    JOIN clip c ON c.id = e.clipID
                    WHERE c.isArchived = 0 AND e.dimension = ? AND e.modelVersion = ?
                    """, arguments: [512, EmbeddingModelInfo.currentVersion]
            ).map { (id: $0["clipID"] as String, vector: $0["vector"] as Data) }
        }
        phases.append(("db-fetch", clock.now - start))

        start = clock.now
        let vectors = rows.map { row in
            row.vector.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        }
        phases.append(("convert", clock.now - start))

        start = clock.now
        let norms = vectors.map { sqrt(vDSP.sumOfSquares($0)) }
        phases.append(("norms", clock.now - start))

        start = clock.now
        let queryNorm = sqrt(vDSP.sumOfSquares(query))
        var scores = [Float](repeating: 0, count: vectors.count)
        for (index, vector) in vectors.enumerated() {
            var dot: Float = 0
            vector.withUnsafeBufferPointer { v in
                query.withUnsafeBufferPointer { q in
                    vDSP_dotpr(v.baseAddress!, 1, q.baseAddress!, 1, &dot, vDSP_Length(v.count))
                }
            }
            let denominator = norms[index] * queryNorm
            scores[index] = denominator > 0 ? dot / denominator : 0
        }
        phases.append(("score", clock.now - start))

        start = clock.now
        let sorted = scores.indices.sorted { scores[$0] > scores[$1] }.prefix(topK)
        phases.append(("full-sort", clock.now - start))

        start = clock.now
        // Bounded insertion selection: O(n·k) with k = topK, no full sort.
        var top: [(offset: Int, element: Float)] = []
        top.reserveCapacity(topK + 1)
        for candidate in scores.enumerated() {
            if top.count < topK {
                top.append(candidate)
                top.sort { $0.element > $1.element }
            } else if candidate.element > top[topK - 1].element {
                top[topK - 1] = candidate
                top.sort { $0.element > $1.element }
            }
        }
        phases.append(("partial-top-k", clock.now - start))

        #expect(
            Array(sorted) == top.map(\.offset),
            "partial selection must pick exactly the full sort's top rows")
        return phases
    }

    @Test("Semantic retrieval: 10k p95 under budget, 100k ceiling documented, memory bounded")
    func semanticRetrievalBudget() async throws {
        let warmRounds = 5
        let tenKBudget = Duration.milliseconds(100)
        let hundredKCeiling = Duration.seconds(2)

        for scale in [10_000, 100_000] {
            let store = GRDBClipboardStore(
                writer: try DatabaseQueue(),
                blobs: BlobStore(
                    directory: FileManager.default.temporaryDirectory
                        .appendingPathComponent("perf-sem-\(UUID().uuidString)")))
            try store.migrate()
            let footprintBefore = residentFootprint()
            let seedStart = ContinuousClock.now
            try await seedEmbeddings(into: store, count: scale)
            print("perf: semantic seeded \(scale)x512 in \(ContinuousClock.now - seedStart)")

            for (name, duration) in try await measurePhases(
                store: store, query: queryVector(), topK: 10)
            {
                print("perf: semantic phase[\(name)] over \(scale): \(duration)")
            }

            // End-to-end through the PRODUCTION query, warm rounds — the cold
            // first call doubles as the repeated-query comparison (no cache
            // exists today; these numbers say whether one is worth building).
            var latencies: [Duration] = []
            for _ in 0..<warmRounds {
                let start = ContinuousClock.now
                let hits = try await store.semanticSearch(queryVector: queryVector(), topK: 10)
                latencies.append(ContinuousClock.now - start)
                #expect(hits.count == 10)
            }
            let summary = LatencySummary(latencies)
            let footprintDelta = residentFootprint() - footprintBefore
            print(
                "perf: semantic end-to-end over \(scale): cold=\(latencies[0]) "
                    + "p95=\(summary.p95) max=\(summary.maximum) "
                    + "footprint-delta=\(footprintDelta / 1_048_576) MiB")

            if scale == 10_000 {
                #expect(summary.p95 < tenKBudget, "10k semantic p95 budget")
            } else {
                // The documented ceiling: a coarse regression tripwire, not a
                // target — production caps history far below 100k embeddings.
                #expect(summary.p95 < hundredKCeiling, "100k semantic ceiling")
                #expect(
                    footprintDelta < 1_200 * 1_048_576,
                    "100k retrieval memory must stay bounded")
            }
        }
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
        let environment = Self.isHostedRunner ? "github-hosted" : "dedicated"
        // Print the budget that is ENFORCED, not the nominal one: a log that
        // says 50 ms while the gate applies 100 ms is how a reader concludes
        // the wrong thing about a passing run.
        print(
            "perf: FTS5 method environment=\(environment) cold=1 warmup=1 "
                + "warm-rounds=\(Self.searchRounds) queries-per-round=\(Self.searchQueries.count) "
                + "cold-budget=\(Self.coldSearchBudget) "
                + "warm-p95-budget=\(Self.effectiveWarmSearchP95Budget) "
                + "warm-p95-budget-strict=\(Self.warmSearchP95Budget)")
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
            warm.p95 < Self.effectiveWarmSearchP95Budget,
            "warm p95 \(warm.p95) blew the \(Self.effectiveWarmSearchP95Budget) budget")
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

    // MARK: - Cold launch: the real pool, on disk, encrypted

    #if SQLITE_HAS_CODEC
        /// The one path a user waits on that nothing else here measures.
        ///
        /// Every other budget in this file runs against an in-memory
        /// `DatabaseQueue`, so its numbers are a lower bound that excludes the
        /// production storage entirely: no `DatabasePool`, no WAL, no disk
        /// latency, and no SQLCipher. Launch is exactly where those cost the
        /// most — `AppModel.init` opens the store synchronously on the main
        /// actor, so whatever this takes is a beachball with no UI behind it.
        ///
        /// The worst realistic case is an UPGRADE launch: `v18-fts-prefix-indexes`
        /// drops the FTS5 table and rebuilds it over every existing row. Seeding
        /// at v17 and then opening normally reproduces that, and the open also
        /// covers the pool, the blob sweep, and the remaining migrations.
        ///
        /// Not covered here, and deliberately: the Keychain read that precedes
        /// the open in production. This uses `init(directory:passphrase:)` so
        /// the harness never touches a developer's keychain.
        @Test("Upgrade launch — open, migrate, and rebuild FTS over 100k encrypted rows")
        func launchOpenAndMigrateBudget() async throws {
            let directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("perf-launch-\(UUID().uuidString)", isDirectory: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let passphrase = try KeychainPassphraseStore.generateKey()

            let seedStart = ContinuousClock.now
            try await seedEncryptedStore(
                at: directory, passphrase: passphrase,
                upTo: GanchoDatabaseMigrator.Identifier.frecencyBoardsInsights.rawValue)
            print(
                "perf: launch seeded \(Self.scale) encrypted clips at v17 in "
                    + "\(ContinuousClock.now - seedStart)")

            // The measured thing: what a user's next launch actually does.
            let start = ContinuousClock.now
            let store = try GRDBClipboardStore(directory: directory, passphrase: passphrase)
            let elapsed = ContinuousClock.now - start
            print(
                "perf: launch open+migrate (v17→current, encrypted pool on disk) over "
                    + "\(Self.scale): \(elapsed) budget=\(Self.launchOpenBudget)")

            // The rebuilt index must actually answer, and must be the v18 shape
            // — otherwise a fast number here would only prove the migration
            // skipped the work this test exists to time.
            #expect(try await !store.search(ClipSearchQuery(text: "deploy")).isEmpty)
            #expect(
                try await ftsDefinition(in: store.writer)?.contains("prefix") == true,
                "the measured open did not rebuild the FTS index with prefix support")
            #expect(
                elapsed < Self.launchOpenBudget,
                "launch open+migrate \(elapsed) blew the \(Self.launchOpenBudget) budget")
        }

        /// Seeds an encrypted on-disk store stopped at `migration`, mirroring the
        /// production pool configuration so the measured open meets the same
        /// file, page size, and journal mode it will meet in the app.
        private func seedEncryptedStore(
            at directory: URL, passphrase: String, upTo migration: String
        ) async throws {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            var configuration = Configuration()
            configuration.maximumReaderCount = 8
            configuration.prepareDatabase { db in try db.usePassphrase(passphrase) }
            let pool = try DatabasePool(
                path: directory.appendingPathComponent("gancho.sqlite").path,
                configuration: configuration)
            let store = GRDBClipboardStore(
                writer: pool,
                blobs: BlobStore(
                    directory: directory.appendingPathComponent("blobs"),
                    encryptionKeyData: BlobStore.encryptionKeyData(for: passphrase)))
            try store.migrate(upTo: migration)
            try await store.importBatch(ClipFixtures.make(count: Self.scale))
            // Prove the seed really stopped short of v18. Without this the test
            // could be timing an already-migrated open — a fast, meaningless
            // number that looks like a pass.
            let seededDefinition = try await ftsDefinition(in: pool)
            #expect(
                seededDefinition?.contains("prefix") != true,
                "the seed was supposed to stop at v17, before the prefix rebuild")
            // Close every connection before the measured reopen, so the timing
            // is a cold open rather than a second handle on a warm pool.
            try pool.close()
        }

        /// The stored `CREATE VIRTUAL TABLE` text for the FTS index, which
        /// carries the `prefix=` option only after v18 rebuilds it.
        private func ftsDefinition(in reader: some DatabaseReader) async throws -> String? {
            try await reader.read { db in
                try String.fetchOne(
                    db, sql: "SELECT sql FROM sqlite_master WHERE name = 'clip_fts'")
            }
        }
    #endif

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

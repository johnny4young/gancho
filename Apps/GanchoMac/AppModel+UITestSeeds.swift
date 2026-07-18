import AppKit
import ClipboardCore
import Foundation
import GanchoKit

/// Deterministic UI-test fixtures, kept out of the production composition-root
/// initializer. Every helper independently requires its `-seed-*` launch
/// argument (and, for the durable ones, the throwaway-store argument) before it
/// writes anything, so a normal launch is a byte-for-byte no-op and a real
/// user's history is never touched. Mirrors `IOSAppModel+UITestSeeds`.
extension AppModel {
    /// Runs every requested `-seed-*` fixture in the original launch order and
    /// returns the durable-seed tasks the `-open-panel-on-launch` flow awaits
    /// before showing the panel. A normal launch returns an empty array.
    func seedUITestFixturesIfRequested() -> [Task<Void, Never>] {
        seedSampleClipsIfRequested()
        seedDenylistEntryIfRequested()
        return [
            seedSampleBoardsIfRequested(),
            seedPanelReproIfRequested(),
            seedSourceAppsIfRequested(),
            seedReuseSuggestionIfRequested(),
            seedClipEditingIfRequested(),
            seedMultiFileDragIfRequested()
        ].compactMap { $0 }
    }

    /// UI-test hook: seed a few KNOWN synthetic clips through the normal capture
    /// pipeline so the panel/history is deterministic for the automated flows.
    /// Strictly gated on BOTH the launch arg and the ephemeral store, so a real
    /// user's durable history is never touched and a normal launch (no arg) is a
    /// byte-for-byte no-op. The seed content is synthetic and non-secret.
    private func seedSampleClipsIfRequested() {
        guard CommandLine.arguments.contains("-seed-sample-clips"), storageIsEphemeral
        else { return }
        for capture in [
            PasteboardCapture(text: "seed alpha"),
            PasteboardCapture(text: "https://seed.example/one"),
            PasteboardCapture(text: "seed beta")
        ] {
            ingest(capture)
        }
    }

    /// UI-test hook: `-seed-denylist-entry <bundle-id>` pre-adds one user
    /// denylist entry so `DenylistUITests` can verify the Settings row and
    /// the remove path with element clicks alone — synthesized typing isn't
    /// grantable on every runner. It requires an isolated test defaults suite,
    /// so a crash can never leave test data in a user's real preferences.
    private func seedDenylistEntryIfRequested() {
        #if DEBUG
            guard let index = CommandLine.arguments.firstIndex(of: "-seed-denylist-entry"),
                Self.uiTestDefaultsSuiteName() != nil,
                CommandLine.arguments.indices.contains(index + 1)
            else { return }
            addToDenylist(CommandLine.arguments[index + 1])
        #endif
    }

    /// Selects a disposable UserDefaults domain for UI tests. The prefix
    /// prevents a launch argument from ever clearing a normal preferences
    /// domain; each test supplies a unique UUID-backed suite name.
    static func defaultsForLaunch() -> UserDefaults {
        #if DEBUG
            guard let suiteName = uiTestDefaultsSuiteName(),
                let defaults = UserDefaults(suiteName: suiteName)
            else { return .standard }
            defaults.removePersistentDomain(forName: suiteName)
            return defaults
        #else
            return .standard
        #endif
    }

    #if DEBUG
        static func uiTestDefaultsSuiteName() -> String? {
            guard let index = CommandLine.arguments.firstIndex(of: "-ui-test-defaults-suite"),
                CommandLine.arguments.indices.contains(index + 1)
            else { return nil }
            let suiteName = CommandLine.arguments[index + 1]
            guard suiteName.hasPrefix("com.johnny4young.gancho.uitests.") else { return nil }
            return suiteName
        }
    #endif

    /// The throwaway store directory for `-use-temp-durable-store`, or nil when
    /// the arg is absent. Lives under the OS temp directory (system-cleaned), so
    /// the UI-test paywall flow gets a REAL durable store — board creation works
    /// and the free-tier gate is reachable — without touching the user's data.
    static func temporaryDurableStoreDirectory() -> URL? {
        guard ProcessInfo.processInfo.arguments.contains("-use-temp-durable-store")
        else { return nil }
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gancho-uitest-store-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// UI-test hook: seed exactly `PinLimits.freeMaxPinboards` known boards into a
    /// THROWAWAY durable store so an automated flow can create ONE more and hit
    /// the free-tier paywall deterministically. Gated on BOTH `-seed-sample-boards`
    /// and `-use-temp-durable-store` (never a real store), so a normal launch is a
    /// no-op and the user's boards are never touched. Seeds sequentially so the
    /// board count is exact when the test creates the next one.
    private func seedSampleBoardsIfRequested() -> Task<Void, Never>? {
        guard CommandLine.arguments.contains("-seed-sample-boards"),
            CommandLine.arguments.contains("-use-temp-durable-store"),
            let grdbStore
        else { return nil }
        return Task {
            for i in 1...PinLimits.freeMaxPinboards {
                _ = try? await grdbStore.createPinboard(
                    name: "Seed board \(i)", sfSymbol: "square.stack")
            }
            await refreshBoards()
        }
    }

    /// UI-test hook: seed source-app metadata into a throwaway durable store so
    /// the filter can be exercised without reading or mutating real history.
    /// Both launch arguments are required; all payloads are synthetic.
    private func seedSourceAppsIfRequested() -> Task<Void, Never>? {
        guard CommandLine.arguments.contains("-seed-source-apps"),
            CommandLine.arguments.contains("-use-temp-durable-store"),
            let grdbStore
        else { return nil }
        return Task {
            let entries: [(text: String, app: String, kind: ClipContentKind)] = [
                ("Safari source alpha", "com.apple.Safari", .text),
                ("Safari source link", "com.apple.Safari", .url),
                ("Xcode source sample", "com.apple.dt.Xcode", .code)
            ]
            let identifiers = [
                "00000000-0000-4000-8000-000000000101",
                "00000000-0000-4000-8000-000000000102",
                "00000000-0000-4000-8000-000000000103"
            ]
            for (index, entry) in entries.enumerated() {
                guard let id = UUID(uuidString: identifiers[index]) else { return }
                let item = ClipItem(
                    id: id,
                    createdAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(index)),
                    kind: entry.kind, preview: entry.text,
                    contentHash: "ui-source-\(index)", sourceAppBundleID: entry.app)
                _ = try? await grdbStore.insert(item, content: .text(entry.text))
            }
            await refreshRecents()
        }
    }

    /// UI-test hook: seed one synthetic clip at two uses so a double-click
    /// drives the real paste-back → atomic third-use → suggestion path. It is
    /// available only with the throwaway durable store.
    private func seedReuseSuggestionIfRequested() -> Task<Void, Never>? {
        guard CommandLine.arguments.contains("-seed-reuse-suggestion"),
            CommandLine.arguments.contains("-use-temp-durable-store"),
            let grdbStore,
            let id = UUID(uuidString: "00000000-0000-4000-8000-000000000104")
        else { return nil }
        return Task {
            let item = ClipItem(
                id: id, preview: "Reusable standup update",
                contentHash: "mac-ui-reuse-suggestion", uses: 2)
            _ = try? await grdbStore.insert(item, content: .text("Reusable standup update"))
            await refreshRecents()
        }
    }

    /// UI-test hook: one deterministic text clip for title/content editing and
    /// large-preview evidence. The throwaway durable-store guard prevents a
    /// normal launch from ever seeding user history.
    private func seedClipEditingIfRequested() -> Task<Void, Never>? {
        guard CommandLine.arguments.contains("-seed-clip-editing"),
            CommandLine.arguments.contains("-use-temp-durable-store"),
            let grdbStore,
            let id = UUID(uuidString: "00000000-0000-4000-8000-000000000105")
        else { return nil }
        return Task {
            let item = ClipItem(
                id: id, preview: "Yesterday: fixed search",
                contentHash: "mac-ui-clip-editing")
            _ = try? await grdbStore.insert(
                item,
                content: .text(
                    "Yesterday: fixed search\nToday: improve editing\nBlockers: none"))
            await refreshRecents()
        }
    }

    /// UI-test hook: seed a THROWAWAY durable store with a few PINNED clips plus
    /// several same-day clips, so a UI test can assert the grouped panel render
    /// keeps exactly one row selected and hands each row a DISTINCT ⌘N shortcut —
    /// the pinned-first + date-bucket global-index math `PanelSearchModel` owns.
    /// Gated on BOTH `-seed-panel-repro` and `-use-temp-durable-store` (never a
    /// real store), so a normal launch is a no-op.
    private func seedPanelReproIfRequested() -> Task<Void, Never>? {
        guard CommandLine.arguments.contains("-seed-panel-repro"),
            CommandLine.arguments.contains("-use-temp-durable-store"),
            let grdbStore
        else { return nil }
        // Fire-and-forget: AFTER the panel is on screen, capture several same-day
        // clips one at a time through the REAL ingest path, so each triggers a
        // live refresh while the grouped list is visible — the reported scenario
        // (a static seed rendered before open does NOT reproduce it).
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(900))
            for text in ["repro today A", "repro today B", "repro today C", "repro today D"] {
                ingest(PasteboardCapture(text: text))
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        // Awaited before the panel opens: the pinned section it sits above.
        return Task {
            var ids: [UUID] = []
            for text in ["repro pinned 1", "repro pinned 2", "repro pinned 3"] {
                let item = ClipItem(kind: .text, preview: text, contentHash: text)
                if let stored = try? await grdbStore.insert(item, content: .text(text)) {
                    ids.append(stored.id)
                }
            }
            for id in ids { _ = try? await grdbStore.setPinned(id: id, true) }
            await refreshRecents()
        }
    }

    /// UI-test hook: creates two harmless temporary files and one pinned clip
    /// that references both. The paired in-panel drop target can then verify
    /// that AppKit exposes two independent dragging items end to end.
    private func seedMultiFileDragIfRequested() -> Task<Void, Never>? {
        guard CommandLine.arguments.contains("-seed-multi-file-drag"),
            CommandLine.arguments.contains("-use-temp-durable-store"),
            let grdbStore
        else { return nil }
        return Task {
            let directory = FileManager.default.temporaryDirectory
                .appending(path: "gancho-multi-file-drag-ui-test", directoryHint: .isDirectory)
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            let urls = ["alpha.txt", "beta.txt"].map { directory.appending(path: $0) }
            for (index, url) in urls.enumerated() {
                try? Data("Gancho drag file \(index + 1)".utf8).write(to: url)
            }
            let item = ClipItem(
                kind: .fileReference,
                title: "Two test files",
                preview: "alpha.txt + beta.txt",
                contentHash: "mac-ui-multi-file-drag")
            if let stored = try? await grdbStore.insert(
                item, content: .fileReferences(urls.map(\.path)))
            {
                _ = try? await grdbStore.setPinned(id: stored.id, true)
            }
            await refreshRecents()
        }
    }
}

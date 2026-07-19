import Foundation
import GanchoKit

extension IOSAppModel {
    /// Centralizes durable synthetic fixtures outside the production
    /// composition-root initializer. Every helper independently requires the
    /// throwaway-store launch argument before writing anything.
    func seedDurableUITestFixturesIfRequested() -> Task<Void, Never>? {
        seedSampleBoardsIfRequested()
        seedSourceAppsIfRequested()
        seedReuseSuggestionIfRequested()
        seedClipEditingIfRequested()
        return seedPrivateActivityReceiptIfRequested()
    }

    private func seedSampleBoardsIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-seed-sample-boards"),
            ProcessInfo.processInfo.arguments.contains("-use-temp-durable-store"),
            let full
        else { return }
        Task {
            for index in 1...PinLimits.freeMaxPinboards {
                _ = try? await full.createPinboard(
                    name: "Seed board \(index)", sfSymbol: "square.stack")
            }
            await refreshBoards()
        }
    }

    private func seedSourceAppsIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-seed-source-apps"),
            ProcessInfo.processInfo.arguments.contains("-use-temp-durable-store"),
            let full
        else { return }
        Task {
            let entries: [(text: String, app: String, kind: ClipContentKind)] = [
                ("Safari source alpha", "com.apple.Safari", .text),
                ("Safari source link", "com.apple.Safari", .url),
                ("Xcode source sample", "com.apple.dt.Xcode", .code)
            ]
            let identifiers = [
                "00000000-0000-4000-8000-000000000201",
                "00000000-0000-4000-8000-000000000202",
                "00000000-0000-4000-8000-000000000203"
            ]
            for (index, entry) in entries.enumerated() {
                guard let id = UUID(uuidString: identifiers[index]) else { return }
                let item = ClipItem(
                    id: id,
                    createdAt: Date(timeIntervalSince1970: 1_800_000_000 + Double(index)),
                    kind: entry.kind, preview: entry.text,
                    contentHash: "ios-ui-source-\(index)", sourceAppBundleID: entry.app)
                _ = try? await full.insert(item, content: .text(entry.text))
            }
            await refreshSourceApps()
            await search()
        }
    }

    private func seedReuseSuggestionIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-seed-reuse-suggestion"),
            ProcessInfo.processInfo.arguments.contains("-use-temp-durable-store"),
            let full,
            let id = UUID(uuidString: "00000000-0000-4000-8000-000000000204")
        else { return }
        Task {
            let item = ClipItem(
                id: id, preview: "Reusable standup update",
                contentHash: "ios-ui-reuse-suggestion", uses: 2)
            _ = try? await full.insert(item, content: .text("Reusable standup update"))
            await search()
        }
    }

    private func seedClipEditingIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-seed-clip-editing"),
            ProcessInfo.processInfo.arguments.contains("-use-temp-durable-store"),
            let full,
            let id = UUID(uuidString: "00000000-0000-4000-8000-000000000205")
        else { return }
        Task {
            let item = ClipItem(
                id: id, preview: "Yesterday: fixed search",
                contentHash: "ios-ui-clip-editing")
            _ = try? await full.insert(
                item,
                content: .text(
                    "Yesterday: fixed search\nToday: improve editing\nBlockers: none"))
            await search()
        }
    }

    private func seedPrivateActivityReceiptIfRequested() -> Task<Void, Never>? {
        guard ProcessInfo.processInfo.arguments.contains("-seed-private-activity-receipt"),
            ProcessInfo.processInfo.arguments.contains("-use-temp-durable-store"),
            let full
        else { return nil }
        return Task {
            let now = Date()
            try? await full.recordPrivateCapture(
                sourceAppBundleID: "com.apple.mobilesafari", count: 12, at: now)
            try? await full.recordPrivateReuse(
                targetAppBundleID: nil, itemCount: 8, at: now)
            try? await full.recordPrivateSkippedCapture(
                isProtected: true, count: 2, at: now)
            try? await full.recordPrivateSensitiveExpiry(count: 1, at: now)
        }
    }
}

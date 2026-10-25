import ClipboardCore
import Foundation
import GanchoAppCore
import GanchoKit
import UIKit

extension IOSAppModel {
    /// Centralizes durable synthetic fixtures outside the production
    /// composition-root initializer. Every helper independently requires the
    /// throwaway-store launch argument before writing anything.
    func seedDurableUITestFixturesIfRequested() -> Task<Void, Never>? {
        seedSampleBoardsIfRequested()
        seedSourceAppsIfRequested()
        seedHomeIfRequested()
        seedReuseSuggestionIfRequested()
        seedClipEditingIfRequested()
        seedOutboundPrivacyIfRequested()
        seedIntentionalCaptureIfRequested()
        return seedPrivateActivityReceiptIfRequested()
    }

    private func seedIntentionalCaptureIfRequested() {
        #if DEBUG
            let arguments = CommandLine.arguments
            guard arguments.contains("-use-temp-durable-store"),
                let index = arguments.firstIndex(of: "-seed-intentional-capture"),
                arguments.indices.contains(index + 1)
            else { return }
            let scenario = arguments[index + 1]
            let text = "Synthetic intentional capture fixture"
            switch scenario {
            case "protected-direct":
                // The marker deliberately belongs to a second item: inspecting
                // only UIPasteboard.types (the first item) is insufficient.
                UIPasteboard.general.items = [
                    ["public.utf8-plain-text": text],
                    [SensitivePasteboardTypes.concealed: Data()]
                ]
                Task { await saveClipboard() }
            case "protected-provider":
                UIPasteboard.general.string = text
                let safe = NSItemProvider(object: text as NSString)
                let protected = NSItemProvider()
                protected.registerDataRepresentation(
                    forTypeIdentifier: SensitivePasteboardTypes.transient, visibility: .all
                ) { completion in
                    completion(Data(), nil)
                    return nil
                }
                ingest(providers: [safe, protected])
            case "safe-text":
                UIPasteboard.general.string = text
                ingest(providers: [NSItemProvider(object: text as NSString)])
            case "safe-image":
                let image = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image {
                    context in
                    UIColor.blue.setFill()
                    context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
                }
                UIPasteboard.general.image = image
                ingest(providers: [NSItemProvider(object: image)])
            default: break
            }
        #endif
    }

    private func seedOutboundPrivacyIfRequested() {
        #if DEBUG
            guard CommandLine.arguments.contains("-seed-outbound-privacy"),
                CommandLine.arguments.contains("-use-temp-durable-store"), let full
            else { return }
            Task {
                let canary = "synthetic-protected-preview-canary"
                let item = ClipItem(kind: .jwt, preview: canary, contentHash: "ui-outbound-privacy")
                _ = try? await full.insert(item, content: .text(canary))
                await search()
            }
        #endif
    }

    #if DEBUG
        /// UI-test hook: `-pin-long-save-note` shows a long real status note
        /// (the load failure, a failure-kind note) and never dismisses it, so a
        /// test can measure the status row and read its kind in any language
        /// and text size. Nothing is read or saved.
        func pinLongSaveNoteIfRequested() {
            guard ProcessInfo.processInfo.arguments.contains("-pin-long-save-note") else { return }
            saveNote = CaptureStatusNote(
                text: String(localized: "Couldn’t load this clip — try again."), kind: .failure)
        }

    #endif

    /// How long a status note stays before `flashNote` dismisses it: two
    /// seconds, or the value of `-ui-test-save-note-lifetime <seconds>` in a
    /// DEBUG build. A hosted UI runner can take longer than two seconds
    /// between two accessibility snapshots, so a test that asserts the REAL
    /// note asks for a longer life and then asserts the dismissal too. Only
    /// the duration changes; what is noted, and when, does not — the dismissal
    /// path runs in every build.
    static func saveNoteLifetime(
        arguments: [String] = ProcessInfo.processInfo.arguments
    )
        -> Duration
    {
        #if DEBUG
            if let index = arguments.firstIndex(of: "-ui-test-save-note-lifetime"),
                arguments.indices.contains(index + 1),
                let seconds = Double(arguments[index + 1]), seconds > 0
            {
                return .seconds(seconds)
            }
        #endif
        return .seconds(2)
    }

    #if DEBUG
        /// `-ui-test-pasteboard-hints link`: the card as if a link were on the
        /// clipboard, without writing to the simulator's (synced) clipboard.
        static func uiTestPinnedHints(
            changeCount: Int, arguments: [String] = ProcessInfo.processInfo.arguments
        ) -> IntentionalPasteboardSource.ContentHints? {
            guard let index = arguments.firstIndex(of: "-ui-test-pasteboard-hints"),
                arguments.indices.contains(index + 1), arguments[index + 1] == "link"
            else { return nil }
            return IntentionalPasteboardSource.ContentHints(
                hasContent: true, probableWebURL: true, changeCount: changeCount)
        }
    #endif

    /// The card's Open window; `-ui-test-saved-open-window` lengthens it for
    /// a hosted runner that samples the screen seconds apart.
    static func recentPasteSaveWindow(
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> TimeInterval {
        #if DEBUG
            if let index = arguments.firstIndex(of: "-ui-test-saved-open-window"),
                arguments.indices.contains(index + 1),
                let seconds = TimeInterval(arguments[index + 1]), seconds > 0
            {
                return seconds
            }
        #endif
        return RecentPasteSave.openWindow
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

    /// `-seed-home-v4`: the v4 Home rows — a clip from another device, a
    /// protected clip with its stored mask and expiry, a link and a pin.
    private func seedHomeIfRequested() {
        #if DEBUG
            guard ProcessInfo.processInfo.arguments.contains("-seed-home-v4"),
                ProcessInfo.processInfo.arguments.contains("-use-temp-durable-store"),
                let full
            else { return }
            Task {
                let now = Date()
                let rows: [(ClipItem, String)] = [
                    (
                        ClipItem(
                            createdAt: now.addingTimeInterval(-3_600), title: "Standup notes",
                            preview: "Ship the onboarding, then the iPhone home",
                            contentHash: "ios-home-pinned", sourceAppBundleID: "com.apple.Notes",
                            isPinned: true),
                        "Ship the onboarding, then the iPhone home"
                    ),
                    (
                        ClipItem(
                            createdAt: now.addingTimeInterval(-420), kind: .url,
                            title: "Synthetic link",
                            preview: "https://www.example.com/a", contentHash: "ios-home-link",
                            sourceAppBundleID: "com.apple.mobilesafari"),
                        "https://www.example.com/a"
                    ),
                    (
                        ClipItem(
                            createdAt: now.addingTimeInterval(-120), kind: .secret,
                            preview: "●●●● 4Q2v", contentHash: "ios-home-secret",
                            sourceAppBundleID: "com.apple.Terminal", isSensitive: true,
                            expiresAt: now.addingTimeInterval(9 * 60)),
                        "synthetic-secret-value-4Q2v"
                    ),
                    (
                        ClipItem(
                            createdAt: now.addingTimeInterval(-60), kind: .code,
                            title: "Example · Swift", preview: "let greeting = \"Hello\"",
                            contentHash: "ios-home-device", sourceAppBundleID: "com.apple.dt.Xcode",
                            sourceDeviceName: "Studio Mac"),
                        "let greeting = \"Hello\""
                    )
                ]
                for (item, text) in rows { _ = try? await full.insert(item, content: .text(text)) }
                // The pinned note doubles as a snippet with a keyword, for the boards home.
                if let note = rows.first?.0 {
                    try? await full.promoteToSnippet(id: note.id, title: "Standup notes")
                    try? await full.setKeyword(id: note.id, keyword: ";standup")
                }
                await search()
            }

        #endif
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

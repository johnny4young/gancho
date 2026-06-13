import AppIntents
import ClipboardCore
import GanchoAI
import GanchoKit
import UIKit

/// The intents ARE the public API: they open the same App Group store and
/// run the same classification pipeline the UI uses — no logic forks.
/// Reachable from Shortcuts, the Action Button, Back Tap, and Spotlight.
enum IntentStore {
    nonisolated static func open() throws -> GRDBClipboardStore {
        try GRDBClipboardStore(
            directory: SharedStorageLocation.storeDirectory(
                appGroupID: SharedInbox.appGroupID))
    }
}

/// Save whatever is on the pasteboard right now (Action Button / Back Tap
/// flagship: capture without opening anything).
struct SaveClipboardIntent: AppIntent {
    static let title: LocalizedStringResource = "Save Clipboard"
    static let description = IntentDescription(
        "Saves the current clipboard into Gancho. iOS shows its standard paste confirmation.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let pasteboard = UIPasteboard.general
        let classifier = RuleClassifier()
        let store = try IntentStore.open()

        if let image = pasteboard.image, let png = image.pngData() {
            let item = ClipItem(
                kind: .image, preview: "Image (\(png.count) bytes)",
                contentHash: ClipItem.hash(of: png, kind: .image))
            try await store.insert(
                item, content: .binary(data: png, typeIdentifier: "public.png"))
            return .result(dialog: "Saved the image to Gancho.")
        }
        guard let text = pasteboard.string, !text.isEmpty else {
            return .result(dialog: "The clipboard is empty.")
        }
        let kind = classifier.classify(text)
        let canonical = ContentNormalizer.canonicalText(text, kind: kind)
        let item = SensitiveIngestionPolicy.decorate(
            ClipItem(
                kind: kind, preview: String(canonical.prefix(120)),
                contentHash: ClipItem.hash(of: canonical, kind: kind)),
            finding: SensitiveDataDetector().detect(canonical), originalText: canonical)
        try await store.insert(item, content: .text(canonical))
        return .result(dialog: "Saved to Gancho.")
    }
}

/// Full-text search over history, returning entities Shortcuts can chain.
struct SearchClipIntent: AppIntent {
    static let title: LocalizedStringResource = "Search Clips"
    static let description = IntentDescription("Finds clips in your Gancho history.")

    @Parameter(title: "Search for")
    var query: String

    func perform() async throws -> some IntentResult & ReturnsValue<[ClipEntity]> {
        let store = try IntentStore.open()
        let hits = try await store.search(ClipSearchQuery(text: query), limit: 10)
        return .result(value: hits.map(ClipEntity.init))
    }
}

/// "Copy the last URL I copied" — the canonical chained-shortcut use case.
struct CopyLastURLIntent: AppIntent {
    static let title: LocalizedStringResource = "Copy Last URL"
    static let description = IntentDescription(
        "Puts the most recent URL from your history back on the clipboard.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = try IntentStore.open()
        // Newest URL by kind (an empty fuzzy query matches nothing).
        let item = try await store.items(offset: 0, limit: 200).first { $0.kind == .url }
        guard let item, case .text(let url)? = try await store.content(for: item.id) else {
            return .result(dialog: "No URLs in your history yet.")
        }
        UIPasteboard.general.string = url
        return .result(dialog: "Copied.")
    }
}

/// Panic button: wipe everything sensitive, now.
struct ClearSensitiveIntent: AppIntent {
    static let title: LocalizedStringResource = "Clear Sensitive Clips"
    static let description = IntentDescription(
        "Deletes every clip Gancho marked as sensitive (keys, cards, passwords).")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let store = try IntentStore.open()
        let removed = try await store.deleteAllSensitive()
        return .result(dialog: "Removed \(removed) sensitive clips.")
    }
}

/// Clips as entities: Shortcuts can pass them around; Spotlight indexes
/// them (semantic schema adoption deepens when the SDK-27 APIs stabilize).
struct ClipEntity: AppEntity, Identifiable {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Clip"
    static let defaultQuery = ClipEntityQuery()

    let id: UUID
    let preview: String
    let kind: String

    init(item: ClipItem) {
        id = item.id
        preview = item.preview
        kind = item.kind.rawValue
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(preview)", subtitle: "\(kind)")
    }
}

struct ClipEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [ClipEntity] {
        let store = try IntentStore.open()
        let ids = Set(identifiers)
        return try await store.items(offset: 0, limit: 500)
            .filter { ids.contains($0.id) }
            .map(ClipEntity.init)
    }

    func suggestedEntities() async throws -> [ClipEntity] {
        let store = try IntentStore.open()
        return try await store.items(offset: 0, limit: 10).map(ClipEntity.init)
    }
}

/// Spotlight/Siri surfacing with zero setup.
struct GanchoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SaveClipboardIntent(),
            phrases: [
                "Save my clipboard in \(.applicationName)",
                "Capture clipboard with \(.applicationName)",
            ],
            shortTitle: "Save Clipboard",
            systemImageName: "square.and.arrow.down")
        AppShortcut(
            intent: ClearSensitiveIntent(),
            phrases: ["Clear sensitive clips in \(.applicationName)"],
            shortTitle: "Clear Sensitive",
            systemImageName: "trash.slash")
    }
}

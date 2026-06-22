import AppIntents
import ClipboardCore
import GanchoAI
import GanchoKit
import UIKit

/// The intents ARE the public API: they open the same App Group store and
/// run the same classification pipeline the UI uses — no logic forks.
/// Reachable from Shortcuts, the Action Button, Back Tap, and Spotlight.
/// `IntentStore` + `SaveClipboardIntent` live in `Apps/GanchoShared` so the
/// widget extension can reuse them (App Intents in a widget need target
/// membership in both the app and the extension).

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

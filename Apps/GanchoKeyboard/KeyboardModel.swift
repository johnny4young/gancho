import GanchoKit
import SwiftUI

/// Backs the keyboard UI. Reads the App Group store (only when Full Access is
/// granted), exposes the pin-first / search list as masked-safe entries, and
/// inserts a clip's REAL content only when the user taps it. Reverse capture
/// goes through the shared `SharedCapture` pipeline.
@MainActor
final class KeyboardModel: ObservableObject {
    @Published var entries: [WidgetClipEntry] = []
    @Published var searchText = ""
    @Published var expanded = false
    @Published var note: LocalizedStringKey?

    let hasFullAccess: Bool
    let onDelete: () -> Void
    let onNextKeyboard: () -> Void
    var onModeChange: ((Bool) -> Void)?

    private let onInsert: (String) -> Void
    private let store: GRDBClipboardStore?

    init(
        hasFullAccess: Bool,
        onInsert: @escaping (String) -> Void,
        onDelete: @escaping () -> Void,
        onNextKeyboard: @escaping () -> Void
    ) {
        self.hasFullAccess = hasFullAccess
        self.onInsert = onInsert
        self.onDelete = onDelete
        self.onNextKeyboard = onNextKeyboard
        // No Full Access → no shared-container access → no store, no clips.
        store = hasFullAccess ? try? IntentStore.open() : nil
    }

    /// Pin-first history (sensitive excluded by `KeyboardClips`).
    func load() async {
        guard let store else { return }
        let all = (try? await store.items(offset: 0, limit: 50)) ?? []
        entries = KeyboardClips.ordered(
            pinned: all.filter(\.isPinned), recent: all.filter { !$0.isPinned })
    }

    func runSearch() async {
        guard let store else { return }
        let trimmed = searchText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            await load()
            return
        }
        let hits = (try? await store.search(ClipSearchQuery(text: trimmed), limit: 30)) ?? []
        entries = WidgetClips.entries(from: hits.filter { !$0.isSensitive }, limit: 30)
    }

    /// Loads the clip's full content and inserts it into the active field.
    func insert(_ entry: WidgetClipEntry) {
        guard let store else { return }
        Task {
            switch try? await store.content(for: entry.id) {
            case .text(let text): onInsert(text)
            case .fileReferences(let paths): onInsert(paths.joined(separator: "\n"))
            default: break  // images aren't insertable as text
            }
        }
    }

    func toggleExpand() {
        expanded.toggle()
        onModeChange?(expanded)
        if expanded { Task { await load() } }
    }

    func saveClipboard() {
        Task {
            note = Self.message(for: await SharedCapture.saveCurrentClipboard())
            await load()
            try? await Task.sleep(for: .seconds(2))
            note = nil
        }
    }

    private static func message(for outcome: SharedCapture.Outcome) -> LocalizedStringKey {
        switch outcome {
        case .savedText, .savedImage: "Saved to Gancho"
        case .empty: "The clipboard is empty"
        case .storeUnavailable: "Couldn’t open Gancho"
        }
    }
}

import GanchoKit
import SwiftUI
import UIKit

/// Backs the keyboard UI. Reads the App Group store (only when Full Access is
/// granted), exposes the pin-first / search list as masked-safe entries, and
/// acts on a tap: text clips insert into the field, image clips copy the real
/// image to the pasteboard (a keyboard can't insert images directly). Reverse
/// capture goes through the shared `SharedCapture` pipeline.
@MainActor
final class KeyboardModel: ObservableObject {
    @Published var entries: [WidgetClipEntry] = []
    @Published var searchText = ""
    @Published var expanded = false
    @Published var note: LocalizedStringKey?
    @Published private(set) var saving = false

    let hasFullAccess: Bool
    let onDelete: () -> Void
    let onNextKeyboard: () -> Void
    var onModeChange: ((Bool) -> Void)?

    private let onInsert: (String) -> Void
    private let store: GRDBClipboardStore?
    private var noteTask: Task<Void, Never>?

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

    /// Acts on a tapped clip: text/file refs insert into the field; images go
    /// to the pasteboard as REAL image data so the host app can paste them
    /// (the keyboard text proxy can't carry an image itself).
    func insert(_ entry: WidgetClipEntry) {
        guard let store else { return }
        Task {
            switch try? await store.content(for: entry.id) {
            case .text(let text):
                onInsert(text)
            case .fileReferences(let paths):
                onInsert(paths.joined(separator: "\n"))
            case .binary(let data, let type):
                UIPasteboard.general.setData(data, forPasteboardType: type)
                flashNote("Image copied — paste it")
            case nil:
                break
            }
        }
    }

    func toggleExpand() {
        expanded.toggle()
        onModeChange?(expanded)
        // No reload here: `entries` is already loaded; reloading caused a flash.
    }

    func saveClipboard() {
        guard !saving else { return }
        saving = true
        Task {
            let outcome = await SharedCapture.saveCurrentClipboard()
            saving = false
            flashNote(Self.message(for: outcome))
            await load()
        }
    }

    /// Shows a transient note and auto-clears it (cancelling any prior timer so
    /// rapid taps don't leave a stale message).
    private func flashNote(_ key: LocalizedStringKey) {
        note = key
        noteTask?.cancel()
        noteTask = Task {
            try? await Task.sleep(for: .seconds(2))
            if !Task.isCancelled { note = nil }
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

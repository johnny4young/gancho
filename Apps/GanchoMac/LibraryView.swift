import AppKit
import GanchoAI
import GanchoDesign
import GanchoKit
import SwiftUI

/// The curated world: browse, edit (with the local syntax tint), and author
/// snippets. All local; the free ceiling gates promotion, not browsing.
struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var snippets: [ClipItem] = []
    @State private var selected: ClipItem?
    @State private var title = ""
    @State private var snippetBody = ""

    var body: some View {
        HSplitView {
            List(
                snippets,
                selection: Binding(
                    get: { selected?.id },
                    set: { id in
                        selected = snippets.first { $0.id == id }
                        title = selected?.title ?? ""
                        Task { await loadBody() }
                    })
            ) { snippet in
                ClipCard(item: snippet).tag(snippet.id)
            }
            .frame(minWidth: 200)

            VStack(alignment: .leading, spacing: GanchoTokens.Spacing.sm) {
                if selected != nil {
                    TextField("Snippet title", text: $title)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("snippet-title")
                    TextEditor(text: $snippetBody)
                        .font(.body.monospaced())
                        .accessibilityIdentifier("snippet-editor")
                    HStack {
                        ActionButton("Save", systemImage: "checkmark", identifier: "snippet-save") {
                            save()
                        }
                        Spacer()
                        ActionButton(
                            "Remove from Library", systemImage: "trash",
                            identifier: "snippet-demote"
                        ) {
                            demote()
                        }
                    }
                } else {
                    Text("Select a snippet, or create one.")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(GanchoTokens.Spacing.sm)
            .frame(minWidth: 280)
        }
        .toolbar {
            ToolbarItem {
                Button {
                    createNew()
                } label: {
                    Label("New snippet", systemImage: "plus")
                }
                .accessibilityIdentifier("snippet-new")
            }
        }
        .frame(minWidth: 560, minHeight: 360)
        .accessibilityIdentifier("library")
        .task { await refresh() }
    }

    private func refresh() async {
        snippets = (try? await model.grdbStore?.snippets()) ?? []
    }

    private func loadBody() async {
        guard let selected,
            case .text(let text)? = try? await model.store.content(for: selected.id)
        else {
            snippetBody = ""
            return
        }
        snippetBody = text
    }

    private func save() {
        guard let selected else { return }
        Task {
            try? await model.grdbStore?.updateSnippet(
                id: selected.id, title: title, text: snippetBody)
            await refresh()
        }
    }

    private func demote() {
        guard let selected else { return }
        Task {
            try? await model.grdbStore?.demoteFromSnippet(id: selected.id)
            self.selected = nil
            await refresh()
        }
    }

    /// Authored snippet: a fresh clip born directly in the library.
    private func createNew() {
        guard let store = model.grdbStore else { return }
        Task {
            let count = (try? await store.snippetCount()) ?? 0
            guard SnippetLimits.canPromote(currentSnippetCount: count, isPro: model.tier == .pro)
            else {
                model.paywallWindow.show(trigger: .freeLimitReached, model: model)
                return
            }
            let text = String(localized: "New snippet")
            let item = ClipItem(
                title: text, preview: text,
                contentHash: ClipItem.hash(of: UUID().uuidString, kind: .text))
            _ = try? await store.insert(item, content: .text(text))
            try? await store.promoteToSnippet(id: item.id, title: text)
            await refresh()
        }
    }
}

@MainActor
final class LibraryWindowController {
    private var window: NSWindow?

    func show(model: AppModel) {
        if window == nil {
            let hosting = NSHostingController(rootView: LibraryView().environment(model))
            let created = NSWindow(contentViewController: hosting)
            created.title = String(localized: "Library")
            created.styleMask = [.titled, .closable, .resizable]
            created.isReleasedWhenClosed = false
            created.center()
            window = created
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

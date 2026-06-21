import AppKit
import ClipboardCore
import GanchoAI
import GanchoDesign
import GanchoKit
import SwiftUI

/// The curated world: browse, search, edit (with live syntax highlighting) and
/// author snippets. Everything is local; the free ceiling gates promotion, not
/// browsing. The editor is the design's "snippet editor" proposal, kept to a
/// faithful, native elevation — a real highlighted code editor, a kind pill,
/// honest metadata, and Save / Copy / Remove — without the tag taxonomy,
/// usage-count tracking, or `{placeholder}` fill-in flow (separate features).
struct LibraryView: View {
    @Environment(AppModel.self) private var model
    @State private var snippets: [ClipItem] = []
    @State private var selected: ClipItem?
    @State private var title = ""
    @State private var snippetBody = ""
    @State private var keyword = ""
    @State private var search = ""
    @State private var snippetCount = 0

    /// Live, case-insensitive filter over the loaded snippets (title + preview).
    private var visible: [ClipItem] {
        guard !search.isEmpty else { return snippets }
        let needle = search.lowercased()
        return snippets.filter {
            $0.title.lowercased().contains(needle) || $0.preview.lowercased().contains(needle)
        }
    }

    var body: some View {
        HSplitView {
            sidebar
            editor
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
        .frame(minWidth: 620, minHeight: 380)
        .accessibilityIdentifier("library")
        .task { await refresh() }
    }

    // MARK: Sidebar — search, list, free-tier count

    private var sidebar: some View {
        VStack(spacing: 0) {
            SearchField("Search snippets", text: $search)
                .padding(GanchoTokens.Spacing.xs)
            List(
                visible,
                selection: Binding(
                    get: { selected?.id },
                    set: { id in
                        selected = snippets.first { $0.id == id }
                        title = selected?.title ?? ""
                        keyword = selected?.keyword ?? ""
                        Task { await loadBody() }
                    })
            ) { snippet in
                ClipCard(item: snippet, isSelected: snippet.id == selected?.id).tag(snippet.id)
            }
            Divider()
            HStack(spacing: GanchoTokens.Spacing.xxs) {
                Text("\(snippetCount) snippets")
                if model.tier != .pro {
                    Text("·")
                    Text("\(max(0, SnippetLimits.freeMaxSnippets - snippetCount)) left on Free")
                }
                Spacer(minLength: 0)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, GanchoTokens.Spacing.sm)
            .padding(.vertical, GanchoTokens.Spacing.xs)
            .accessibilityIdentifier("snippet-count")
        }
        .frame(minWidth: 240)
    }

    // MARK: Editor

    @ViewBuilder private var editor: some View {
        if let selected {
            VStack(alignment: .leading, spacing: GanchoTokens.Spacing.sm) {
                TextField("Snippet title", text: $title)
                    .textFieldStyle(.plain)
                    .font(.title2.weight(.semibold))
                    .accessibilityIdentifier("snippet-title")

                HStack(spacing: GanchoTokens.Spacing.xs) {
                    kindPill(selected.kind)
                    keywordField
                    Spacer(minLength: 0)
                }

                SyntaxTextView(text: $snippetBody)
                    .frame(minHeight: 220)
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: GanchoTokens.Radius.md, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
                            .strokeBorder(.separator, lineWidth: GanchoTokens.Stroke.hairline)
                    )

                let fields = SnippetTemplate.fields(in: snippetBody)
                if !fields.isEmpty {
                    fieldStrip(fields)
                }

                footer(for: selected)
            }
            .padding(GanchoTokens.Spacing.md)
            .frame(minWidth: 340)
        } else {
            Text("Select a snippet, or create one.")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .frame(minWidth: 340)
        }
    }

    /// Read-only kind label — uses the classifier's `ClipContentKind`, never a
    /// fabricated per-language guess.
    private func kindPill(_ kind: ClipContentKind) -> some View {
        Label(LocalizedStringKey(kind.rawValue), systemImage: kind.symbolName)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, GanchoTokens.Spacing.xs)
            .padding(.vertical, GanchoTokens.Spacing.xxs)
            .background(.quaternary, in: Capsule())
            .accessibilityIdentifier("snippet-kind")
    }

    /// The snippet's invocation keyword: typing it in the panel surfaces this
    /// snippet, and a template ({fields}) is filled before paste.
    private var keywordField: some View {
        HStack(spacing: 4) {
            Image(systemName: "bolt.fill")
                .font(.caption2)
                .foregroundStyle(GanchoTokens.Palette.accent)
            TextField("Keyword", text: $keyword)
                .textFieldStyle(.plain)
                .font(.callout.monospaced())
                .frame(maxWidth: 160)
                .accessibilityIdentifier("snippet-keyword")
        }
        .padding(.horizontal, GanchoTokens.Spacing.xs)
        .padding(.vertical, GanchoTokens.Spacing.xxs)
        .background(.quaternary, in: Capsule())
    }

    /// The {placeholders} detected in the template — filled when the snippet is
    /// inserted by keyword.
    private func fieldStrip(_ fields: [SnippetTemplate.Field]) -> some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xxs) {
            Text("Fields").font(.caption2).foregroundStyle(.secondary)
            HStack(spacing: GanchoTokens.Spacing.xxs) {
                ForEach(fields) { field in
                    Text(verbatim: "{\(field.name)}")
                        .font(.caption.monospaced())
                        .padding(.horizontal, GanchoTokens.Spacing.xs)
                        .padding(.vertical, 2)
                        .background(
                            GanchoTokens.Palette.kindTint(for: .code).opacity(0.15), in: Capsule()
                        )
                        .foregroundStyle(GanchoTokens.Palette.kindTint(for: .code))
                }
            }
        }
    }

    private func footer(for snippet: ClipItem) -> some View {
        HStack(spacing: GanchoTokens.Spacing.sm) {
            Group {
                Label(
                    "Created \(snippet.createdAt.formatted(date: .abbreviated, time: .omitted))",
                    systemImage: "clock"
                )
                Label("\(snippetBody.count) characters", systemImage: "text.alignleft")
                if snippet.uses > 0 {
                    Label("\(snippet.uses) uses", systemImage: "arrow.up.right")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            ActionButton(
                "Remove from Library", systemImage: "trash", identifier: "snippet-demote"
            ) {
                demote()
            }
            .foregroundStyle(GanchoTokens.Palette.danger)
            ActionButton("Copy", systemImage: "doc.on.doc", identifier: "snippet-copy") {
                SystemPasteboardWriter().write(.text(snippetBody), asPlainText: true)
            }
            ActionButton("Save", systemImage: "checkmark", identifier: "snippet-save") {
                save()
            }
        }
    }

    // MARK: Data

    private func refresh() async {
        snippets = (try? await model.grdbStore?.snippets()) ?? []
        snippetCount = (try? await model.grdbStore?.snippetCount()) ?? snippets.count
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
            try? await model.grdbStore?.setKeyword(id: selected.id, keyword: keyword)
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
            let hosting = NSHostingController(
                rootView: LibraryView().environment(model).ganchoTinted())
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

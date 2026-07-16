import AppKit
import ClipboardCore
import GanchoAI
import GanchoDesign
import GanchoKit
import SwiftUI

// LibraryView intentionally keeps the sidebar, board scope, and snippet editor
// together until the Library split can be reviewed as a dedicated UI refactor.
// swiftlint:disable type_body_length
/// The unified Library (the design's "Library + Pro"): a sidebar that navigates
/// two worlds — BOARDS (All clips · Pinned · Favorites · your boards, each with
/// a live count) and LIBRARY · SNIPPETS (keyword-triggered `{placeholder}`
/// templates). Selecting a board shows its clips as a card grid; selecting a
/// snippet opens the editor. Everything is local; the free ceiling gates
/// creation, not browsing.
struct LibraryView: View {
    // swiftlint:enable type_body_length
    @Environment(AppModel.self) private var model

    /// What the sidebar has selected; `nil` is treated as "All clips".
    @State private var selection: LibrarySelection? = .allClips
    @State private var boards: [Pinboard] = []
    @State private var boardCounts: [UUID: Int] = [:]
    @State private var allCount = 0
    @State private var pinnedCount = 0
    @State private var clips: [ClipItem] = []
    @State private var snippets: [ClipItem] = []

    // Snippet editor state (the right pane when a snippet is selected).
    @State private var editingSnippet: ClipItem?
    @State private var title = ""
    @State private var snippetBody = ""
    @State private var keyword = ""
    @FocusState private var focusedField: EditorField?

    // Board name prompt (create / rename).
    @State private var boardSheet: BoardSheet?
    @State private var boardNameField = ""
    /// The board a destructive "Delete board" is awaiting confirmation on.
    @State private var boardPendingDeletion: Pinboard?
    @State private var boardAppearanceTarget: Pinboard?

    private enum EditorField { case title, keyword }

    var body: some View {
        HSplitView {
            sidebar
                .frame(minWidth: 232, idealWidth: 252, maxWidth: 320)
            detail
                .frame(minWidth: 460, maxWidth: .infinity)
        }
        .frame(minWidth: 800, minHeight: 560)
        .accessibilityIdentifier("library")
        .task { await refreshAll() }
        .onChange(of: selection) { _, _ in Task { await loadScope() } }
        .onChange(of: model.syncStatus) { _, status in
            // A finished sync may have pulled new boards/clips — refresh so they
            // appear here without reopening the window.
            if status != .syncing { Task { await refreshAll() } }
        }
        .alert(boardSheetTitle, isPresented: boardSheetPresented) {
            TextField("Board name", text: $boardNameField)
            Button("Cancel", role: .cancel) {}
            Button(boardSheetConfirm) { commitBoardSheet() }
        }
        .confirmationDialog(
            "Delete this board?",
            isPresented: Binding(
                get: { boardPendingDeletion != nil },
                set: { if !$0 { boardPendingDeletion = nil } }),
            presenting: boardPendingDeletion
        ) { board in
            Button("Delete board", role: .destructive) { deleteBoard(board) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Your clips stay in history — only the board is removed.")
        }
        .sheet(item: $boardAppearanceTarget) { board in
            BoardIdentityEditor(board: board) { colorHex, emoji in
                let saved = await model.updateBoardIdentity(
                    board, colorHex: colorHex, emoji: emoji)
                if saved { await refreshAll() }
                return saved
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(spacing: 0) {
            List(selection: $selection) {
                Section {
                    navRow(.allClips, Text("All clips"), systemImage: "tray.full", count: allCount)
                    navRow(.pinned, Text("Pinned"), systemImage: "pin", count: pinnedCount)
                    ForEach(boards) { board in
                        navRow(
                            .board(board.id),
                            boardTitle(board),
                            systemImage: board.sfSymbol, count: boardCounts[board.id] ?? 0,
                            board: board
                        )
                        .contextMenu {
                            if !board.isSystem {
                                Button("Customize board…") {
                                    boardAppearanceTarget =
                                        boards.first { $0.id == board.id } ?? board
                                }
                                Button("Rename board…") {
                                    boardNameField = board.name
                                    boardSheet = .rename(board)
                                }
                                Button("Delete board", role: .destructive) {
                                    boardPendingDeletion = board
                                }
                            }
                        }
                    }
                } header: {
                    sectionHeader(Text("Boards"), identifier: "board-new", badge: boardLimitBadge) {
                        boardNameField = ""
                        boardSheet = .new
                    }
                }

                Section {
                    if snippets.isEmpty {
                        Text("No snippets yet")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    ForEach(snippets) { snippet in
                        snippetRow(snippet).tag(LibrarySelection.snippet(snippet.id))
                    }
                } header: {
                    sectionHeader(
                        Text("Library · Snippets"), identifier: "snippet-new",
                        badge: snippetLimitBadge
                    ) {
                        createSnippet()
                    }
                }
            }
            proFooter
        }
        .frame(minWidth: 232)
    }

    private func navRow(
        _ selectionValue: LibrarySelection, _ label: Text, systemImage: String, count: Int,
        board: Pinboard? = nil
    ) -> some View {
        HStack(spacing: GanchoTokens.Spacing.xs) {
            if let board {
                BoardIdentityMark(board: board, size: 14).frame(width: 18)
            } else {
                Image(systemName: systemImage)
                    .frame(width: 18)
                    .foregroundStyle(.secondary)
            }
            label.lineLimit(1)
            Spacer(minLength: 0)
            if count > 0 {
                Text(verbatim: "\(count)")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .tag(selectionValue)
    }

    private func boardTitle(_ board: Pinboard) -> Text {
        board.isSystem ? Text("Favorites") : Text(verbatim: board.name)
    }

    private func snippetRow(_ snippet: ClipItem) -> some View {
        HStack(spacing: GanchoTokens.Spacing.xs) {
            Image(systemName: "text.alignleft")
                .frame(width: 18)
                .foregroundStyle(.secondary)
            if snippet.title.isEmpty {
                Text("Untitled").lineLimit(1).foregroundStyle(.secondary)
            } else {
                Text(verbatim: snippet.title).lineLimit(1)
            }
            Spacer(minLength: 0)
            if let keyword = snippet.keyword, !keyword.isEmpty {
                Image(systemName: "return")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .help(Text(verbatim: keyword))
            }
        }
    }

    private func sectionHeader(
        _ label: Text, identifier: String, badge: Text? = nil, add: @escaping () -> Void
    )
        -> some View
    {
        HStack {
            label
            if let badge {
                badge.font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
            }
            Spacer()
            Button(action: add) {
                Image(systemName: "plus")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier(identifier)
        }
    }

    /// Free users see a live `used/limit` count by each section so the ceiling
    /// is visible BEFORE they hit it (Pro browses without a counter).
    private var userBoardCount: Int { boards.filter { !$0.isSystem }.count }

    private var boardLimitBadge: Text? {
        guard model.tier != .pro else { return nil }
        return Text(verbatim: "\(userBoardCount)/\(PinLimits.freeMaxPinboards)")
    }

    private var snippetLimitBadge: Text? {
        guard model.tier != .pro else { return nil }
        return Text(verbatim: "\(snippets.count)/\(SnippetLimits.freeMaxSnippets)")
    }

    /// The footer line escalates as the free user fills up: neutral → soft
    /// "almost full" → "limit reached", so the upsell forewarns instead of
    /// ambushing at the wall.
    private var proFooterSubtitle: LocalizedStringKey {
        switch FreeTierLimits.pressure(
            boardsUsed: userBoardCount, snippetsUsed: snippets.count, isPro: model.tier == .pro)
        {
        case .comfortable: "Unlimited boards & snippets"
        case .almostFull: "Almost full — Pro unlocks unlimited"
        case .reached: "Free limit reached — go unlimited"
        }
    }

    /// The upsell that doubles as a status (the design's footer card). Hidden
    /// for Pro; opens the contextual paywall on Free.
    @ViewBuilder private var proFooter: some View {
        if model.tier != .pro {
            Button {
                model.paywallWindow.show(trigger: .freeLimitReached, model: model)
            } label: {
                HStack(spacing: GanchoTokens.Spacing.xs) {
                    Image(systemName: "star.fill")
                        .foregroundStyle(GanchoTokens.Palette.accent)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: "gancho Pro").font(.caption.weight(.semibold))
                        Text(proFooterSubtitle)
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                .padding(GanchoTokens.Spacing.sm)
                .background(
                    GanchoTokens.Palette.accent.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(GanchoTokens.Spacing.xs)
            .accessibilityIdentifier("library-pro")
        }
    }

    // MARK: - Detail

    @ViewBuilder private var detail: some View {
        if case .snippet = selection, let snippet = editingSnippet {
            snippetEditor(snippet)
        } else {
            boardDetail
        }
    }

    /// A board's clips as a card grid, with the scope title, a live count, and
    /// the sync state — the design's main pane.
    private var boardDetail: some View {
        VStack(spacing: 0) {
            HStack(spacing: GanchoTokens.Spacing.xs) {
                scopeTitle.font(.headline)
                Text("\(clips.count) clips").foregroundStyle(.secondary)
                Spacer(minLength: 0)
                SyncStatusView(status: model.syncStatus)
            }
            .padding(GanchoTokens.Spacing.md)

            Divider()

            if clips.isEmpty {
                emptyScope
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [
                            GridItem(.adaptive(minimum: 208), spacing: GanchoTokens.Spacing.sm)
                        ],
                        spacing: GanchoTokens.Spacing.sm
                    ) {
                        ForEach(clips) { clip in
                            clipCard(clip)
                        }
                    }
                    .padding(GanchoTokens.Spacing.md)
                }
            }
        }
    }

    private var scopeTitle: Text {
        switch selection ?? .allClips {
        case .allClips: Text("All clips")
        case .pinned: Text("Pinned")
        case .board(let id):
            if let board = boards.first(where: { $0.id == id }) {
                if board.isSystem {
                    Text("Favorites")
                } else {
                    Text(verbatim: board.name)
                }
            } else {
                Text("All clips")
            }
        case .snippet: Text("All clips")
        }
    }

    private var emptyScope: some View {
        VStack(spacing: GanchoTokens.Spacing.xs) {
            Image(systemName: "tray")
                .font(.system(size: 26))
                .foregroundStyle(.tertiary)
            Text("Nothing here yet")
                .font(.headline)
            Text("Add clips to this board from the history panel, or right-click a clip here.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(GanchoTokens.Spacing.lg)
        .accessibilityIdentifier("library-empty")
    }

    /// One clip in the grid: kind glyph (or colour swatch), title, preview, and
    /// the full set of management actions on right-click. A click copies it.
    private func clipCard(_ clip: ClipItem) -> some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xxs) {
            HStack(spacing: GanchoTokens.Spacing.xxs) {
                if clip.kind == .color, let color = Color(hexString: clip.preview) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(color).frame(width: 14, height: 14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .strokeBorder(.separator, lineWidth: GanchoTokens.Stroke.hairline))
                } else {
                    Image(systemName: clip.kind.symbolName)
                        .font(.caption)
                        .foregroundStyle(GanchoTokens.Palette.kindTint(for: clip.kind))
                }
                cardTitle(clip).font(.callout.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 0)
                if clip.isPinned {
                    Image(systemName: "pin.fill").font(.caption2).foregroundStyle(.secondary)
                }
            }
            Text(verbatim: clip.preview)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(GanchoTokens.Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .background(.background.secondary, in: roundedCard)
        .overlay(roundedCard.strokeBorder(.separator, lineWidth: GanchoTokens.Stroke.hairline))
        .contentShape(Rectangle())
        .onTapGesture { copy(clip) }
        .contextMenu { clipMenu(clip) }
        .accessibilityIdentifier("library-clip")
    }

    private var roundedCard: RoundedRectangle {
        RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
    }

    private func cardTitle(_ clip: ClipItem) -> Text {
        clip.title.isEmpty
            ? Text(LocalizedStringKey(clip.kind.rawValue)) : Text(verbatim: clip.title)
    }

    @ViewBuilder private func clipMenu(_ clip: ClipItem) -> some View {
        Button(clip.isPinned ? "Unpin" : "Pin") { mutate { model.togglePin(clip) } }
        Menu("Add to board") {
            ForEach(boards) { board in
                Button {
                    mutate { model.assign(clip, toBoard: board) }
                } label: {
                    if board.isSystem {
                        Text("Favorites")
                    } else {
                        Text(verbatim: board.name)
                    }
                }
            }
        }
        if case .board(let boardID) = selection,
            let board = boards.first(where: { $0.id == boardID })
        {
            Button("Remove from board") { mutate { model.unassign(clip, fromBoard: board) } }
        }
        Button("Save as snippet") { mutate { model.promoteToSnippet(clip) } }
        Divider()
        Button("Copy", systemImage: "doc.on.doc") { copy(clip) }
        Button("Delete", role: .destructive) { mutate { model.delete(clip) } }
    }

    // MARK: - Snippet editor

    private func snippetEditor(_ snippet: ClipItem) -> some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.sm) {
            TextField("Snippet title", text: $title)
                .textFieldStyle(.plain)
                .font(.title2.weight(.semibold))
                .focused($focusedField, equals: .title)
                .onSubmit { save() }
                .accessibilityIdentifier("snippet-title")

            HStack(spacing: GanchoTokens.Spacing.xs) {
                kindPill(snippet.kind)
                keywordField
                Spacer(minLength: 0)
            }

            SyntaxTextView(text: $snippetBody)
                .frame(minHeight: 220)
                .clipShape(roundedCard)
                .overlay(
                    roundedCard.strokeBorder(.separator, lineWidth: GanchoTokens.Stroke.hairline))

            Text(
                // swiftlint:disable:next line_length
                "Type the keyword in the panel to insert this snippet. Add {field} placeholders to fill in before pasting."
            )
            .font(.caption2)
            .foregroundStyle(.tertiary)

            let fields = SnippetTemplate.fields(in: snippetBody)
            if !fields.isEmpty {
                fieldStrip(fields)
            }

            snippetFooter(for: snippet)
        }
        .padding(GanchoTokens.Spacing.md)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onChange(of: focusedField) { previous, _ in
            // Commit a rename or keyword edit the moment focus leaves the field —
            // no need to hunt for Save for those quick edits.
            if previous == .title || previous == .keyword { save() }
        }
    }

    private func kindPill(_ kind: ClipContentKind) -> some View {
        Label(LocalizedStringKey(kind.rawValue), systemImage: kind.symbolName)
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, GanchoTokens.Spacing.xs)
            .padding(.vertical, GanchoTokens.Spacing.xxs)
            .background(.quaternary, in: Capsule())
            .accessibilityIdentifier("snippet-kind")
    }

    private var keywordField: some View {
        HStack(spacing: 4) {
            Image(systemName: "bolt.fill")
                .font(.caption2)
                .foregroundStyle(GanchoTokens.Palette.accent)
            TextField("Keyword", text: $keyword)
                .textFieldStyle(.plain)
                .font(.callout.monospaced())
                .frame(maxWidth: 160)
                .focused($focusedField, equals: .keyword)
                .onSubmit { save() }
                .accessibilityIdentifier("snippet-keyword")
        }
        .padding(.horizontal, GanchoTokens.Spacing.xs)
        .padding(.vertical, GanchoTokens.Spacing.xxs)
        .background(.quaternary, in: Capsule())
    }

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

    private func snippetFooter(for snippet: ClipItem) -> some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.sm) {
            HStack(spacing: GanchoTokens.Spacing.md) {
                Label(
                    "Created \(snippet.createdAt.formatted(date: .abbreviated, time: .omitted))",
                    systemImage: "clock"
                )
                Label("\(snippetBody.count) characters", systemImage: "text.alignleft")
                if snippet.uses > 0 {
                    Label("\(snippet.uses) uses", systemImage: "arrow.up.right")
                }
                Spacer(minLength: 0)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)

            HStack(spacing: GanchoTokens.Spacing.xs) {
                ActionButton(
                    "Move to history", systemImage: "arrow.uturn.backward",
                    identifier: "snippet-demote"
                ) {
                    demote()
                }
                .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                ActionButton("Copy", systemImage: "doc.on.doc", identifier: "snippet-copy") {
                    SystemPasteboardWriter().write(.text(snippetBody), asPlainText: true)
                    model.toasts.show(GanchoToast(message: "Copied"))
                }
                ActionButton("Save", systemImage: "checkmark", identifier: "snippet-save") {
                    save()
                }
            }
        }
    }

    // MARK: - Data

    private func refreshAll() async {
        boards = (try? await model.grdbStore?.pinboards()) ?? []
        snippets = (try? await model.grdbStore?.snippets()) ?? []
        await refreshCounts()
        await loadScope()
    }

    private func refreshCounts() async {
        allCount = (try? await model.store.count()) ?? 0
        pinnedCount = (try? await model.grdbStore?.pinnedCount()) ?? 0
        var counts: [UUID: Int] = [:]
        for board in boards {
            counts[board.id] = (try? await model.grdbStore?.count(inBoard: board.id)) ?? 0
        }
        boardCounts = counts
    }

    /// Loads whatever the current selection points at: a board's clips, or a
    /// snippet's editable title/keyword/body.
    private func loadScope() async {
        switch selection ?? .allClips {
        case .allClips:
            clips = (try? await model.store.items(offset: 0, limit: 200)) ?? []
            editingSnippet = nil
        case .pinned:
            clips = ((try? await model.store.items(offset: 0, limit: 200)) ?? []).filter(\.isPinned)
            editingSnippet = nil
        case .board(let id):
            // Bounded like the sibling scopes above — the Library is a manager,
            // not a scroll-through; huge boards browse in the panel.
            clips = (try? await model.grdbStore?.items(inBoard: id, offset: 0, limit: 200)) ?? []
            editingSnippet = nil
        case .snippet(let id):
            editingSnippet = snippets.first { $0.id == id }
            title = editingSnippet?.title ?? ""
            keyword = editingSnippet?.keyword ?? ""
            await loadBody()
        }
    }

    /// Re-runs the model action, then reloads the scope + counts once the write
    /// settles (the model methods kick their own tasks). Every Library mutation
    /// funnels through here, so this is also where the curated Spotlight set
    /// stays in step (snippet saves, edits, demotes).
    private func mutate(_ action: () -> Void) {
        action()
        Task {
            try? await Task.sleep(for: .milliseconds(140))
            await loadScope()
            await refreshCounts()
            model.refreshSpotlight()
        }
    }

    private func copy(_ clip: ClipItem) {
        Task {
            if case .text(let text)? = try? await model.store.content(for: clip.id) {
                SystemPasteboardWriter().write(.text(text), asPlainText: false)
            } else {
                SystemPasteboardWriter().write(.text(clip.preview), asPlainText: true)
            }
            model.toasts.show(GanchoToast(message: "Copied"))
        }
    }

    private func loadBody() async {
        guard let editingSnippet,
            case .text(let text)? = try? await model.store.content(for: editingSnippet.id)
        else {
            snippetBody = ""
            return
        }
        snippetBody = text
    }

    private func save() {
        guard let editingSnippet else { return }
        // Capture target + values NOW (synchronously). The async write must not
        // read @State later — by then a different snippet may be selected, and
        // we'd save this snippet's text onto that one.
        persist(id: editingSnippet.id, title: title, body: snippetBody, keyword: keyword)
    }

    private func persist(id: UUID, title: String, body: String, keyword: String) {
        Task {
            try? await model.grdbStore?.updateSnippet(id: id, title: title, text: body)
            try? await model.grdbStore?.setKeyword(id: id, keyword: keyword)
            snippets = (try? await model.grdbStore?.snippets()) ?? []
            // An edited snippet must replace its Spotlight donation at once —
            // text the user just rewrote out of it must not stay searchable.
            model.refreshSpotlight()
        }
    }

    private func demote() {
        guard let editingSnippet else { return }
        Task {
            try? await model.grdbStore?.demoteFromSnippet(id: editingSnippet.id)
            selection = .allClips
            await refreshAll()
            // Un-curating removes the donation immediately, matching the
            // Settings copy's promise.
            model.refreshSpotlight()
        }
    }

    private func createSnippet() {
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
            snippets = (try? await store.snippets()) ?? []
            selection = .snippet(item.id)
            model.refreshSpotlight()
        }
    }

    // MARK: - Board management

    private func deleteBoard(_ board: Pinboard) {
        if selection == .board(board.id) { selection = .allClips }
        model.deleteBoard(board)
        Task {
            try? await Task.sleep(for: .milliseconds(140))
            await refreshAll()
        }
    }

    private var boardSheetPresented: Binding<Bool> {
        Binding(get: { boardSheet != nil }, set: { if !$0 { boardSheet = nil } })
    }

    private var boardSheetTitle: LocalizedStringKey {
        if case .rename = boardSheet { return "Rename board" }
        return "New board"
    }

    private var boardSheetConfirm: LocalizedStringKey {
        if case .rename = boardSheet { return "Rename" }
        return "Create"
    }

    private func commitBoardSheet() {
        let name = boardNameField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let sheet = boardSheet
        boardSheet = nil
        switch sheet {
        case .new:
            Task {
                await model.createBoard(named: name)
                try? await Task.sleep(for: .milliseconds(140))
                await refreshAll()
            }
        case .rename(let board):
            model.renameBoard(board, name: name)
            Task {
                try? await Task.sleep(for: .milliseconds(140))
                await refreshAll()
            }
        case nil: break
        }
    }
}

/// What the Library sidebar can have selected. Boards browse clips; a snippet
/// opens the editor.
private enum LibrarySelection: Hashable {
    case allClips
    case pinned
    case board(UUID)
    case snippet(UUID)
}

/// Drives the new-board / rename-board name prompt.
private enum BoardSheet: Identifiable {
    case new
    case rename(Pinboard)

    var id: String {
        switch self {
        case .new: "new"
        case .rename(let board): board.id.uuidString
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
            // Open roomy and never let it shrink below the two-pane layout's needs.
            created.setContentSize(NSSize(width: 900, height: 640))
            created.contentMinSize = NSSize(width: 800, height: 560)
            created.center()
            window = created
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

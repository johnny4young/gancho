import AppKit
import ClipboardCore
import GanchoAI
import GanchoAppCore
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
    @Environment(AppModel.self) var model

    /// What the sidebar has selected; `nil` is treated as "All clips".
    @State private var selection: LibrarySelection? = .allClips
    @State private var boards: [Pinboard] = []
    @State private var boardCounts: [UUID: Int] = [:]
    @State private var allCount = 0
    @State private var pinnedCount = 0
    @State private var clips: [ClipItem] = []
    @State private var snippets: [ClipItem] = []
    @State private var filterDraft: SmartCollectionRule?
    @State private var filterNeedsEditing = false
    @State private var loadingPage = false
    @State private var reachedEnd = false
    @State private var loadGeneration = UUID()

    // Snippet editor state (the right pane when a snippet is selected).
    @State private var editingSnippet: ClipItem?
    @State var title = ""
    @State var snippetBody = ""
    @State var keyword = ""
    @FocusState var focusedField: EditorField?

    // Board name prompt (create / rename).
    @State private var boardSheet: LibraryBoardSheet?
    @State private var boardNameField = ""
    /// The board a destructive "Delete board" is awaiting confirmation on.
    @State private var boardPendingDeletion: Pinboard?
    @State private var boardAppearanceTarget: Pinboard?

    enum EditorField { case title, keyword }

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
        .sheet(item: $filterDraft) { rule in
            SavedFilterEditor(rule: rule, boards: boards) {
                let saved = await model.savedFilters.save($0)
                if saved { await loadScope() }
                return saved
            }
        }
        .onChange(of: selection) { _, _ in Task { await loadScope() } }
        .onChange(of: model.recentItems) { previous, current in
            // A saved filter is live: a local capture, delete, edit, or pin that
            // moves the recents must show here without switching scopes.
            var savedFilterSelected = false
            if case .savedFilter = selection { savedFilterSelected = true }
            if LibraryScopeReload.isNeeded(
                savedFilterSelected: savedFilterSelected, previous: previous, current: current)
            {
                Task { await loadScope() }
            }
        }
        .onChange(of: model.syncStatus) { _, status in
            // A finished sync may have pulled new boards/clips — refresh so they
            // appear here without reopening the window.
            if status != .syncing { Task { await refreshAll() } }
        }
        .alert(boardSheetTitle, isPresented: boardSheetPresented) {
            TextField("Board name", text: $boardNameField)
            Button("Cancel", role: .cancel) {}
            Button(boardSheetConfirm) { commitLibraryBoardSheet() }
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

    var roundedCard: RoundedRectangle {
        RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
    }

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

                Section("Saved filters") {
                    ForEach(model.savedFilters.rules) { rule in
                        Text(verbatim: rule.name).tag(LibrarySelection.savedFilter(rule.id))
                            .accessibilityIdentifier("saved-filter-row")
                            .contextMenu {
                                Button("Edit filter…") { filterDraft = rule }
                                Button("Delete filter", role: .destructive) {
                                    Task {
                                        await model.savedFilters.delete(rule.id)
                                        if selection == .savedFilter(rule.id) {
                                            selection = .allClips
                                        }
                                    }
                                }
                            }
                    }
                    if model.savedFilters.failed {
                        Text("Saved filters couldn’t be loaded.")
                            .font(.caption)
                        Button("Retry") { model.reloadSavedFilters() }
                            .buttonStyle(.link)
                            .font(.caption)
                            .accessibilityIdentifier("saved-filters-retry")
                    } else if model.savedFilters.legacyImportFailed {
                        Text("Older saved filters couldn’t be imported; the ones here are intact.")
                            .font(.caption)
                            .accessibilityIdentifier("saved-filters-import-warning")
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
                    .accessibilityIdentifier("library-scope-count")
                Spacer(minLength: 0)
                SyncStatusView(status: model.syncStatus)
            }
            .padding(GanchoTokens.Spacing.md)

            Divider()

            if filterNeedsEditing {
                Text(
                    "This filter needs editing: its board is missing or its expression is invalid."
                )
                .padding().accessibilityIdentifier("saved-filter-needs-editing")
            } else if clips.isEmpty {
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
                                .task {
                                    if clip.id == clips.last?.id { await loadMore() }
                                }
                        }
                    }
                    .padding(GanchoTokens.Spacing.md)
                }
                .accessibilityIdentifier("library-clips-scroll")
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
        case .savedFilter(let id):
            Text(verbatim: model.savedFilters.rules.first { $0.id == id }?.name ?? "")
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

    /// Keep copy as the primary action and retain all management commands.
    private func clipCard(_ clip: ClipItem) -> some View {
        Button {
            copy(clip)
        } label: {
            LibraryClipCard(
                clip: clip, thumbnails: model.libraryThumbnails,
                previewsHidden: model.preferences.isPrivateModePaused)
        }
        .buttonStyle(.plain)
        .contextMenu { clipMenu(clip) }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("library-clip")
    }

    @ViewBuilder private func clipMenu(_ clip: ClipItem) -> some View {
        if model.canCopyImageText(clip) {
            Button("Copy text from image") { model.copyImageText(clip) }
                .accessibilityIdentifier("image-copy-text")
        }
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
            .accessibilityIdentifier("library-copy-action")
        Button("Delete", role: .destructive) { mutate { model.delete(clip) } }
    }

    // MARK: - Data

    private func refreshAll() async {
        boards = (try? await model.fullStore?.pinboards()) ?? []
        snippets = (try? await model.fullStore?.snippets()) ?? []
        await refreshCounts()
        await loadScope()
    }

    private func refreshCounts() async {
        allCount = (try? await model.store.count()) ?? 0
        pinnedCount = (try? await model.fullStore?.pinnedCount()) ?? 0
        var counts: [UUID: Int] = [:]
        for board in boards {
            counts[board.id] = (try? await model.fullStore?.count(inBoard: board.id)) ?? 0
        }
        boardCounts = counts
    }

    /// Loads whatever the current selection points at: a board's clips, or a
    /// snippet's editable title/keyword/body.
    private func loadScope() async {
        let generation = UUID()
        loadGeneration = generation
        reachedEnd = false
        loadingPage = false
        filterNeedsEditing = false
        switch selection ?? .allClips {
        case .savedFilter(let id):
            // A saved filter is one ranked, bounded result set — it never pages.
            editingSnippet = nil
            reachedEnd = true
            guard let rule = model.savedFilters.rules.first(where: { $0.id == id }) else {
                clips = []
                return
            }
            do {
                let matches =
                    try await model.fullStore?.items(
                        matching: rule, limit: (rule.textContains ?? "").isEmpty ? 500 : 100) ?? []
                guard generation == loadGeneration else { return }
                let ranked =
                    !(rule.textContains ?? "").isEmpty || rule.kinds != nil
                    || rule.sourceAppBundleID != nil || rule.pinnedOnly
                clips = ranked ? FrecencyRanker.reranked(matches) : matches
            } catch {
                guard generation == loadGeneration else { return }
                clips = []
                filterNeedsEditing = true
            }
        case .snippet(let id):
            editingSnippet = snippets.first { $0.id == id }
            title = editingSnippet?.title ?? ""
            keyword = editingSnippet?.keyword ?? ""
            await loadBody()
        default:
            editingSnippet = nil
            clips = []
            await loadMore()
        }
    }

    /// Pages through `LibraryPager`, so a page that never arrived (the last
    /// card's `.task` is cancelled whenever it scrolls out) leaves the scope
    /// open for the next request, and rows that moved under the loaded list
    /// (retention, a capture, a pin flip) are reconciled rather than skipped.
    private func loadMore() async {
        guard !loadingPage, !reachedEnd else { return }
        let scope = selection ?? .allClips
        let generation = loadGeneration
        loadingPage = true
        defer { if generation == loadGeneration { loadingPage = false } }
        let outcome: LibraryPager.Outcome
        switch scope {
        case .allClips:
            outcome = await LibraryPager.nextPage(loaded: clips) {
                try await model.store.items(offset: $0, limit: $1)
            }
        case .pinned:
            // The store orders pins before all unpinned rows, so this walks
            // the complete pinned prefix rather than an arbitrary recent page.
            outcome = await LibraryPager.nextPage(
                loaded: clips, stopAt: { !$0.isPinned },
                fetch: { try await model.store.items(offset: $0, limit: $1) })
        case .board(let id):
            guard let fullStore = model.fullStore else { return }
            outcome = await LibraryPager.nextPage(loaded: clips) {
                try await fullStore.items(inBoard: id, offset: $0, limit: $1)
            }
        case .snippet, .savedFilter: return
        }
        guard generation == loadGeneration, scope == selection ?? .allClips,
            case .loaded(let rows, let reachedEnd) = outcome
        else { return }
        clips = rows
        self.reachedEnd = reachedEnd
    }

    /// Re-runs the model action, then reloads the scope + counts once the write
    /// settles (the model methods kick their own tasks). Every Library mutation
    /// funnels through here, so this is also where the curated Spotlight set
    /// stays in step (snippet saves, edits, demotes).
    /// The one sleep left, and deliberately so for now. Unlike the board
    /// mutations, these actions are genuinely fire-and-forget: `delete(_:)`
    /// opens the six-second undo window and MUST return immediately, so there
    /// is nothing here to await. The principled replacement is `StoreChangeBus`
    /// — which already exists for exactly this ("the mutation site posts once,
    /// and every consumer that cares is already subscribed") — but today only
    /// `refreshSpotlight` posts to it, so wiring the mutation sites is its own
    /// change rather than a rider on this one.
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
        let revision = NSPasteboard.general.changeCount
        Task {
            guard !model.preferences.isPrivateModePaused,
                !model.pendingDeletionIDs.contains(clip.id),
                let current = try? await model.store.item(id: clip.id),
                !ClipSafePresentation.requiresMasking(current),
                current.expiresAt.map({ $0 > .now }) ?? true,
                let content = try? await model.store.content(for: clip.id),
                let latest = try? await model.store.item(id: clip.id),
                !Task.isCancelled, !model.preferences.isPrivateModePaused,
                !model.pendingDeletionIDs.contains(clip.id),
                !ClipSafePresentation.requiresMasking(latest),
                latest.expiresAt.map({ $0 > .now }) ?? true,
                latest.updatedAt == current.updatedAt, latest.kind == current.kind,
                latest.contentHash == current.contentHash,
                revision == NSPasteboard.general.changeCount
            else { return }
            #if DEBUG
                if !CommandLine.arguments.contains("-ui-test-paste-sink") {
                    SystemPasteboardWriter().write(content, asPlainText: false)
                }
            #else
                SystemPasteboardWriter().write(content, asPlainText: false)
            #endif
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

    func save() {
        guard let editingSnippet else { return }
        // Capture target + values NOW (synchronously). The async write must not
        // read @State later — by then a different snippet may be selected, and
        // we'd save this snippet's text onto that one.
        persist(id: editingSnippet.id, title: title, body: snippetBody, keyword: keyword)
    }

    private func persist(id: UUID, title: String, body: String, keyword: String) {
        Task {
            // The list below reconciles from the store either way, so the UI
            // stays honest — but an edit that did not save must SAY so, the
            // way createSnippet already does. Silently reverting text the user
            // typed reads as a bug in the editor.
            do {
                try await model.fullStore?.updateSnippet(id: id, title: title, text: body)
                try await model.fullStore?.setKeyword(id: id, keyword: keyword)
            } catch {
                model.diagnostics.record(
                    String(localized: "Snippets"),
                    String(localized: "Couldn’t save that snippet."))
            }
            snippets = (try? await model.fullStore?.snippets()) ?? []
            // An edited snippet must replace its Spotlight donation at once —
            // text the user just rewrote out of it must not stay searchable.
            model.refreshSpotlight()
        }
    }

    func demote() {
        guard let editingSnippet else { return }
        Task {
            try? await model.fullStore?.demoteFromSnippet(id: editingSnippet.id)
            selection = .allClips
            await refreshAll()
            // Un-curating removes the donation immediately, matching the
            // Settings copy's promise.
            model.refreshSpotlight()
        }
    }

    private func createSnippet() {
        guard let store = model.fullStore else { return }
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
            do {
                _ = try await store.insert(item, content: .text(text))
                try await store.promoteToSnippet(id: item.id, title: text)
                model.recordActivationMilestone(.firstSnippetCreated)
            } catch {
                model.diagnostics.record("Snippets", "Couldn’t save the snippet.")
                return
            }
            snippets = (try? await store.snippets()) ?? []
            selection = .snippet(item.id)
            model.refreshSpotlight()
        }
    }

    // MARK: - Board management

    private func deleteBoard(_ board: Pinboard) {
        Task {
            // Selection moves only once the board is actually gone. It used to
            // move first and then sleep 140 ms hoping the delete had landed —
            // so a failed delete left the user looking at All clips with the
            // board still in the sidebar.
            let deleted = await model.deleteBoard(board)
            if deleted, selection == .board(board.id) { selection = .allClips }
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

    private func commitLibraryBoardSheet() {
        let name = boardNameField.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let sheet = boardSheet
        boardSheet = nil
        switch sheet {
        case .new:
            Task {
                await model.createBoard(named: name)
                await refreshAll()
            }
        case .rename(let board):
            Task {
                await model.renameBoard(board, name: name)
                await refreshAll()
            }
        case nil: break
        }
    }
}

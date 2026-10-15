import AppKit
import ClipboardCore
import GanchoAI
import GanchoAppCore
import GanchoDesign
import GanchoKit
import SwiftUI

/// Browsing presentation and store adaptation, separate from snippet draft ownership.
extension LibraryView {
    // MARK: - Detail

    @ViewBuilder var detail: some View {
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
            if metadataLoadFailed, !clips.isEmpty {
                libraryReadFailure { Task { await refreshAll() } }
            }

            if metadataLoadFailed, clips.isEmpty {
                libraryReadFailure { Task { await refreshAll() } }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if clipList.failure == .invalidFilter {
                Text(
                    "This filter needs editing: its board is missing or its expression is invalid."
                )
                .padding().accessibilityIdentifier("saved-filter-needs-editing")
            } else if clipList.isLoading && clips.isEmpty {
                ProgressView("Loading clips…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("library-loading")
            } else if clipList.failure == .unavailable && clips.isEmpty {
                libraryReadFailure { Task { await clipList.retry() } }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                                    if clip.id == clips.last?.id { await clipList.loadMore() }
                                }
                        }
                    }
                    .padding(GanchoTokens.Spacing.md)
                    if clipList.failure == .unavailable {
                        libraryReadFailure { Task { await clipList.retry() } }
                    } else if clipList.isLoading {
                        ProgressView("Loading clips…").padding(GanchoTokens.Spacing.sm)
                    }
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
                board.displayTitle
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
            Text(emptyScopeMessage)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(GanchoTokens.Spacing.lg)
        .accessibilityIdentifier("library-empty")
    }

    private var emptyScopeMessage: LocalizedStringKey {
        switch selection ?? .allClips {
        case .allClips, .snippet: "Copy something to start your history."
        case .pinned: "Pin a clip from the history panel to keep it here."
        case .board: "Add clips to this board from the history panel, or right-click a clip here."
        case .savedFilter: "No clips match this filter."
        }
    }

    private func libraryReadFailure(retry: @escaping () -> Void) -> some View {
        HStack(spacing: GanchoTokens.Spacing.sm) {
            Label("Clips couldn’t be loaded. Try again.", systemImage: "exclamationmark.triangle")
                .font(.callout).foregroundStyle(.secondary)
            Button("Retry", action: retry)
                .accessibilityIdentifier("library-retry-button")
        }
        .padding(GanchoTokens.Spacing.md)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library-load-failed-note")
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
        Button(clip.isPinned ? "Unpin" : "Pin") { model.togglePin(clip) }
        Menu("Add to board") {
            ForEach(boards) { board in
                Button {
                    model.assign(clip, toBoard: board)
                } label: {
                    board.displayTitle
                }
            }
        }
        if case .board(let boardID) = selection,
            let board = boards.first(where: { $0.id == boardID })
        {
            Button("Remove from board") { model.unassign(clip, fromBoard: board) }
        }
        Button("Save as snippet") { model.promoteToSnippet(clip) }
        Divider()
        Button("Copy", systemImage: "doc.on.doc") { copy(clip) }
            .accessibilityIdentifier("library-copy-action")
        Button("Delete", role: .destructive) { model.delete(clip) }
    }

    // MARK: - Data

    var clipList: LibraryClipListModel { model.libraryClips }

    /// Pending deletes disappear immediately and return on Undo; the encrypted
    /// store and the list model keep them until the undo window commits.
    var clips: [ClipItem] {
        clipList.items.filter { !model.pendingDeletionIDs.contains($0.id) }
    }

    func refreshAll() async {
        let request = UUID()
        metadataGeneration = request
        do {
            let nextBoards = try await model.fullStore?.pinboards() ?? []
            let nextSnippets = try await model.fullStore?.snippets() ?? []
            let nextAllCount = try await model.store.count()
            let nextPinnedCount = try await model.fullStore?.pinnedCount() ?? 0
            var counts: [UUID: Int] = [:]
            for board in nextBoards {
                counts[board.id] = try await model.fullStore?.count(inBoard: board.id) ?? 0
            }
            guard metadataGeneration == request, !Task.isCancelled else { return }
            boards = nextBoards
            snippets = nextSnippets
            allCount = nextAllCount
            pinnedCount = nextPinnedCount
            boardCounts = counts
            metadataLoadFailed = false
            await loadScope(preservingWindow: true)
        } catch {
            guard metadataGeneration == request, !Task.isCancelled else { return }
            metadataLoadFailed = true
        }
    }

    /// Snippet drafts stay in the editor; browsing requests and pagination live
    /// in the tested model and cannot overwrite editor state asynchronously.
    func loadScope(preservingWindow: Bool = false) async {
        let generation = UUID()
        loadGeneration = generation
        if case .snippet(let id) = selection {
            clipList.cancel()
            await loadSnippet(id: id, generation: generation)
            return
        }
        editingSnippet = nil
        draft = SnippetDraft()
        let scope: LibraryClipScope
        switch selection ?? .allClips {
        case .allClips: scope = .allClips
        case .pinned: scope = .pinned
        case .board(let id): scope = .board(id)
        case .savedFilter(let id):
            guard let rule = model.savedFilters.rules.first(where: { $0.id == id }) else {
                selection = .allClips
                return
            }
            scope = .savedFilter(rule)
        case .snippet: return
        }
        await clipList.reload(scope, preservingWindow: preservingWindow)
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

    // MARK: - Board management

    func deleteBoard(_ board: Pinboard) {
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

    var boardSheetPresented: Binding<Bool> {
        Binding(get: { boardSheet != nil }, set: { if !$0 { boardSheet = nil } })
    }

    var boardSheetTitle: LocalizedStringKey {
        if case .rename = boardSheet { return "Rename board" }
        return "New board"
    }

    var boardSheetConfirm: LocalizedStringKey {
        if case .rename = boardSheet { return "Rename" }
        return "Create"
    }

    func commitLibraryBoardSheet() {
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

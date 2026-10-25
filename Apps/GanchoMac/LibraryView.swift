import AppKit
import ClipboardCore
import GanchoAI
import GanchoAppCore
import GanchoDesign
import GanchoKit
import SwiftUI

/// The unified Library (the design's "Library + Pro"): a sidebar that navigates
/// two worlds — BOARDS (All clips · Pinned · Favorites · your boards, each with
/// a live count) and LIBRARY · SNIPPETS (keyword-triggered `{placeholder}`
/// templates). Selecting a board shows its clips as a card grid; selecting a
/// snippet opens the editor. Everything is local; the free ceiling gates
/// creation, not browsing.
struct LibraryView: View {
    @Environment(AppModel.self) var model
    @Environment(\.accessibilityReduceMotion) var reduceMotion

    /// What the sidebar has selected; `nil` is treated as "All clips".
    @State var selection: LibrarySelection? = .allClips
    @State var boards: [Pinboard] = []
    @State var boardCounts: [UUID: Int] = [:]
    @State var allCount = 0
    @State var pinnedCount = 0
    @State var snippets: [ClipItem] = []
    @State var filterDraft: SmartCollectionRule?
    @State var metadataGeneration = UUID()
    @State var metadataLoadFailed = false
    @State var loadGeneration = UUID()
    @State private var refreshDeferred = false

    // Snippet editor state (the right pane when a snippet is selected).
    @State var editingSnippet: ClipItem?
    @State var draft = SnippetDraft()
    @State var isSavingDraft = false
    @State var draftIsProtected = false
    @State var pendingDraftSelection: LibrarySelection?
    @State var showsDraftResolution = false
    @State var selectionTask: Task<Void, Never>?
    @FocusState var focusedField: EditorField?

    // Board name prompt (create / rename).
    @State var boardSheet: LibraryBoardSheet?
    @State var boardNameField = ""
    /// The board a destructive "Delete board" is awaiting confirmation on.
    @State var boardPendingDeletion: Pinboard?
    @State var boardAppearanceTarget: Pinboard?

    // Browse controls: search, kind chip, sort and layout.
    @State var searchText = ""
    @State var kindFilter: ClipKindFilter = .all
    @State var oldestFirst = false
    @State var layout: LibraryLayout = .grid
    @FocusState var searchFocused: Bool
    /// The sidebar holds focus when the window opens, so its selection reads as active.
    @FocusState var sidebarFocused: Bool
    /// Boards of the clips on screen, read once per page.
    @State var membership: [UUID: Set<UUID>] = [:]
    @State var filterCounts: [UUID: Int] = [:]

    enum EditorField { case title, keyword }

    /// The panes plus the browse controls' observers, split from `body` so it type-checks.
    private var browser: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HSplitView {
                sidebar
                    .frame(minWidth: 232, idealWidth: 252, maxWidth: 320)
                detail
                    .frame(minWidth: 460, maxWidth: .infinity)
            }
        }
        .frame(minWidth: 800, minHeight: 560)
        .onAppear { layout = model.libraryLayout }
        .task {
            // AppKit hands the window's first responder to the search field; take it back.
            try? await Task.sleep(for: .milliseconds(50))
            sidebarFocused = true
        }
        .onChange(of: layout) { _, next in model.libraryLayout = next }
        .onChange(of: kindFilter) { _, _ in Task { await loadScope() } }
        .onChange(of: oldestFirst) { _, _ in Task { await loadScope() } }
        .task(id: searchText) {
            // Typing settles before the store is asked.
            guard (try? await Task.sleep(for: .milliseconds(200))) != nil else { return }
            await loadScope()
        }
        .task(id: clipList.items.map(\.id)) {
            let next = await model.libraryMembership(for: clipList.items)
            guard !Task.isCancelled else { return }
            membership = next
        }
    }

    var body: some View {
        Group {
            browser
        }
        .background { ToastUndoShortcut().opacity(0).accessibilityHidden(true) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("library")
        .task {
            let changes = model.storeChanges.subscribe()
            await refreshAll()
            for await _ in StoreChangeCoalescer().batches(of: changes) {
                guard !Task.isCancelled else { return }
                guard model.libraryWindow.isVisible else {
                    refreshDeferred = true
                    continue
                }
                await refreshAll()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .ganchoLibraryDidShow)) { _ in
            refreshDeferred = false
            Task { await refreshAll() }
        }
        .onReceive(
            NotificationCenter.default.publisher(for: NSWindow.didDeminiaturizeNotification)
        ) { notification in
            guard refreshDeferred, model.libraryWindow.owns(notification.object) else { return }
            refreshDeferred = false
            Task { await refreshAll() }
        }
        .onChange(of: model.savedFilters.rules) { _, rules in
            if case .savedFilter = selection {
                Task { await loadScope(preservingWindow: true) }
            }
            Task { filterCounts = await model.savedFilterCounts(rules) }
        }
        .onDisappear {
            metadataGeneration = UUID()
            loadGeneration = UUID()
            clipList.cancel()
        }
        .sheet(item: $filterDraft) { rule in
            SavedFilterEditor(rule: rule, boards: boards) {
                let saved = await model.savedFilters.save($0)
                if saved { await loadScope() }
                return saved
            }
        }
        .onChange(of: selection) { _, _ in
            Task { await loadScope() }
        }
        .confirmationDialog("Keep your unsaved snippet?", isPresented: $showsDraftResolution) {
            Button("Save as new snippet") { recoverDraft() }
            Button("Discard draft", role: .destructive) { discardDraft() }
            Button("Cancel", role: .cancel) { pendingDraftSelection = nil }
                .accessibilityIdentifier("snippet-resolution-cancel-button")
        } message: {
            Text(
                "The original snippet was removed. Save your changes as a new snippet or discard them before leaving."
            )
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

}

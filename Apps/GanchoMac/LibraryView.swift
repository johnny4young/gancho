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
        .onChange(of: model.savedFilters.rules) { _, _ in
            if case .savedFilter = selection { Task { await loadScope(preservingWindow: true) } }
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

import AppKit
import ClipboardCore
import Combine
import GanchoAI
import GanchoAppCore
import GanchoDesign
import GanchoKit
import SwiftUI

// PanelView remains the main keyboard/navigation owner while stable
// presentation slices move into focused views and tested app-layer policies.
// swiftlint:disable file_length

/// The localized pill labels for the type-filter rail. `ClipKindFilter` itself
/// (cases + `matches`/`tintKind`) lives in `GanchoAppCore` so `PanelSearchModel`
/// can narrow results without importing SwiftUI.
extension ClipKindFilter {
    var title: LocalizedStringKey {
        switch self {
        case .all: "All"
        case .links: "Links"
        case .code: "Code"
        case .colors: "Colors"
        case .images: "Images"
        case .secrets: "Secrets"
        }
    }

    /// The chip glyph: the kind's own symbol, or a grid for "All".
    var symbolName: String {
        tintKind?.symbolName ?? "square.grid.2x2"
    }
}

/// Drives the new-board / rename-board name prompt. `newForClip` is the
/// per-clip "Add to board → New board…" path: it prompts for a name, then files
/// that clip into the board it creates.
private enum BoardSheet: Identifiable {
    case new
    case newForClip(ClipItem)
    case rename(Pinboard)

    var id: String {
        switch self {
        case .new: "new"
        case .newForClip(let clip): "new-\(clip.id.uuidString)"
        case .rename(let board): board.id.uuidString
        }
    }
}

/// Which zone owns the keyboard: the search field (list navigation) or the
/// peek (its action list). → moves focus into the peek, ← returns to the list.
enum PanelFocus: Hashable { case search, peek }

// PanelView owns coordinated search, rails, peek, and sheet state; keep the
// size exception local while those remaining responsibilities are split.
// swiftlint:disable type_body_length
/// The floating history panel: compact, keyboard-first (the explicit design
/// decision vs Paste's full-width drawer). Every interaction works without
/// a mouse: type-to-search, ↑↓ to navigate, → into the peek, Enter to paste.
struct PanelView: View {
    // swiftlint:enable type_body_length
    @Environment(AppModel.self) private var model
    @State private var combinedSelection: CombinedTextSelection?
    @State private var filterDraft: SmartCollectionRule?
    @FocusState private var focus: PanelFocus?
    /// The search + list state (query, results, filters, selection, paging,
    /// grouping) — lifted into `PanelSearchModel` so it is `@Observable` and
    /// unit-testable; the view keeps presentation only.
    @State private var search: PanelSearchModel
    /// Selected-clip preview identity, loading, and editability. The model
    /// rejects stale/cancelled results before the peek can render them.
    @State private var preview: PanelPreviewModel
    /// Non-nil when the keyboard moved up into the filter/board rails.
    @State private var railFocus: RailFocus?
    @State private var boardSheet: BoardSheet?
    @State private var boardNameField = ""
    /// The board a destructive "Delete board" is awaiting confirmation on.
    @State private var boardPendingDeletion: Pinboard?
    @State private var presentedSheet: PanelSheetPresentations.Sheet?
    /// "Ask your clipboard": the grounded answer + its source clips, and whether
    /// the on-device model is currently answering.
    @State private var answer: AppModel.ClipboardAnswer?
    @State private var isAsking = false
    @State private var askTask: Task<Void, Never>?
    /// The keyboard cheat-sheet overlay (⌘/ or the footer "?"): surfaces the
    /// power shortcuts (⌘P/⌘S/⌥⏎/⌘1-9) that the footer hints can't fit.
    @State private var showShortcuts = false
    /// The ⌘B board picker overlay for the selected clip.
    @State private var showBoardPicker = false
    /// ⌘↑/⌘↓ search recall: the loaded recall list (newest first), the
    /// cursor into it, and the entry we last applied — so `onChange` can tell
    /// "user typed" (ends the session) from "we recalled" (keeps it).
    @State private var searchHistory: [String] = []
    @State private var historyCursor: Int?
    @State private var recalledQuery: String?
    /// Set only by the opt-in debug probe used by the signed drag smoke.
    @State private var uiTestPreparedFileCount = 0
    @State private var uiTestStartedFileCount = 0
    @AppStorage private var panelTextSizeRaw: String
    /// One selection highlight shared by every row (see `ClipCard`).
    @Namespace private var selectionNamespace

    init(model: AppModel, displayDefaults: UserDefaults = .standard) {
        _search = State(wrappedValue: PanelSearchModel(source: model))
        _preview = State(wrappedValue: PanelPreviewModel())
        _panelTextSizeRaw = AppStorage(
            wrappedValue: PanelTextSize.standard.rawValue,
            PanelTextSize.storageKey,
            store: displayDefaults)
    }

    /// Zero-size buttons that claim command-level shortcuts. The search
    /// field is the first responder for type-to-search, so a plain key handler
    /// never sees ⌘V — the field editor consumes it as native "paste" and dumps
    /// the clipboard into the query. A keyboardShortcut is resolved as a command
    /// (ahead of the field editor), so ⌘V pastes the SELECTED clip like Enter.
    private var commandShortcutButtons: some View {
        Group {
            Button("") { if let item = search.selectedItem { model.paste(item) } }
                .keyboardShortcut("v", modifiers: .command)
            Button("") {
                if let item = search.selectedItem { model.paste(item, asPlainText: true) }
            }
            .keyboardShortcut("v", modifiers: [.command, .option])
            Button("") {
                if let item = search.selectedItem {
                    model.panel.showLargePreview(item, model: model)
                }
            }
            .keyboardShortcut("y", modifiers: .command)
            // ⇧⌘C reads the selected image's text into the peek. Return keeps
            // pasting; the OCR action never takes position 0 of the peek list.
            Button("") {
                if let item = search.selectedItem { model.copyImageText(item, surface: .peek) }
            }
            .keyboardShortcut("c", modifiers: [.command, .shift])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    var body: some View {
        let panelTextSize = PanelTextSize.resolved(panelTextSizeRaw)
        // ONE surface for list and peek. The peek opens BESIDE the list (not a
        // modal) and follows the selected clip, Quick-Look-style, but it is part
        // of the same panel: a hairline separates the panes, never a gap, and
        // the status footer spans both.
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 0) {
                listColumn
                    .frame(minWidth: 360, idealWidth: 440, maxWidth: .infinity)
                if let selected = search.selectedItem {
                    let presentation = preview.presentation(for: selected)
                    Divider()
                    ClipPeek(
                        item: selected,
                        text: presentation.text,
                        isTextEditable: presentation.isTextEditable,
                        focus: $focus
                    )
                    // Drafts, async save callbacks, and action state belong to
                    // one clip only. A new selection gets a fresh preview identity.
                    .id(selected.id)
                    .frame(minWidth: 320, idealWidth: 400, maxWidth: .infinity)
                    .transition(.opacity)
                }
            }
            statusFooter
        }
        // Every modal layer (shortcut card, board picker, consent prompt) is
        // drawn INSIDE the glass and clipped to it. Applied outside, their dim
        // would paint the window's transparent shell — title-bar band and all
        // — and reveal an outline the panel never shows otherwise.
        .overlay { PanelShortcutsOverlay(isPresented: $showShortcuts) }
        .overlay { boardPickerOverlay }
        .overlay { telemetryConsentPrompt }
        .overlay(alignment: .top) { uiTestMultiFileDropTarget }
        .clipShape(RoundedRectangle(cornerRadius: GanchoTokens.Radius.lg, style: .continuous))
        .ganchoSurface(radius: GanchoTokens.Radius.lg)
        // The glass IS the panel: it fills the window edge to edge, title-bar
        // band included, so there is no transparent ring for AppKit's window
        // outline to show through.
        .ignoresSafeArea()
        .frame(minWidth: 720, minHeight: 460)
        .dynamicTypeSize(panelTextSize.dynamicTypeSize)
        .background {
            #if DEBUG
                if CommandLine.arguments.contains("-opaque-panel-for-ui-test") {
                    Color(nsColor: .windowBackgroundColor)
                }
            #endif
        }
        .background { commandShortcutButtons }
        .animation(.snappy(duration: 0.12), value: showShortcuts)
        .task {
            await search.refreshSourceApps()
            await search.refresh()
        }
        .task { await model.refreshBoards() }
        .sheet(item: $combinedSelection) { selection in
            CombinedTextReview(ids: selection.ids).environment(model)
        }
        .sheet(item: $filterDraft) { rule in
            SavedFilterEditor(rule: rule, boards: model.boards) {
                await model.savedFilters.save($0)
            }
        }
        .onChange(of: search.query) { _, newValue in
            // A new query invalidates a previous answer and drops rail focus
            // (you're typing in the search field again).
            askTask?.cancel()
            askTask = nil
            isAsking = false
            answer = nil
            railFocus = nil
            // Mirror the live query so a paste knows the search that led to it
            // Typing anything that isn't a recalled entry ends the
            // ⌘↑ recall session.
            model.activePanelQuery = newValue
            if newValue != recalledQuery {
                historyCursor = nil
                searchHistory = []
                recalledQuery = nil
            }
            Task {
                let interval = Signpost.queryToResults.begin()
                await search.refresh()
                Signpost.queryToResults.end(interval)
            }
        }
        .onChange(of: model.recentItems) { _, _ in
            Task {
                await search.refreshSourceApps()
                await search.refresh()
            }
        }
        // Keyed on the pending set, not on `recentItems`: a delete filters the
        // recent list synchronously, but an UNDO only schedules an async
        // refresh, so watching the list would reconcile on the way out and not
        // on the way back. This fires on both, synchronously, before the
        // refresh — the visible list is cached now, so without it a row lingers
        // for a store round trip and reads as "not deleted".
        .onChange(of: model.pendingDeletionIDs) { _, _ in
            search.reconcileVisible()
        }
        .onChange(of: search.selectedBoardID) { _, _ in
            Task { await search.refresh() }
        }
        .onChange(of: search.selectedSourceAppBundleID) { _, _ in
            Task { await search.refresh() }
        }
        // The kind filter narrows client-side, so regroup without a re-query.
        .onChange(of: search.kindFilter) { _, _ in Task { await search.refresh() } }
        .modifier(
            PanelSheetPresentations(
                boardSheetTitle: boardSheetTitle,
                boardSheetConfirm: boardSheetConfirm,
                boardSheetPresented: boardSheetPresented,
                boardNameField: $boardNameField,
                boardPendingDeletion: $boardPendingDeletion,
                presentedSheet: $presentedSheet,
                commitBoardSheet: commitBoardSheet,
                deleteBoard: { board in
                    Task {
                        // Leave the board only once it is actually gone. This
                        // used to clear first, so a failed delete dropped the
                        // panel on All clips with the board still in the rail —
                        // the same mismatch `LibraryView.deleteBoard` fixes.
                        // Clearing the id is itself what refreshes the list
                        // (the `onChange` above), so nothing else is needed.
                        let deleted = await model.deleteBoard(board)
                        if deleted, search.selectedBoardID == board.id {
                            search.selectedBoardID = nil
                        }
                    }
                },
                pasteSnippet: { request, values in
                    model.pasteSnippet(request.snippet, values: values)
                },
                updateBoardIdentity: { board, colorHex, emoji in
                    await model.updateBoardIdentity(board, colorHex: colorHex, emoji: emoji)
                })
        )
        // Load the peek for the selected clip, keyed on its id and debounced:
        // arrowing fast cancels the in-flight load, so only the clip you land on
        // is read and rendered — keeps navigation responsive.
        .task(id: search.selectedItem?.id) {
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            let store = model.store
            await preview.load(search.selectedItem) { id in
                try await store.content(for: id)
            }
        }
        .onAppear {
            // First visible frame: close the panel-open latency interval the
            // controller began in show().
            model.panel.notePanelDidAppear()
            // Defer one runloop: on the FIRST open the field editor isn't
            // ready when onAppear fires, so an immediate focus is dropped
            // (arrow keys beep). The notification below re-grabs it on every
            // key transition, which covers first open and reopens alike.
            DispatchQueue.main.async { focus = .search }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) {
            notification in
            guard let window = notification.object as? NSWindow,
                model.panel.isPanelWindow(window)
            else { return }
            focus = .search
        }
    }

    /// A DEBUG-only, launch-argument-gated real drop destination. It exercises
    /// the same pasteboard handoff as another app without making the UI test
    /// drag across arbitrary windows on the developer's desktop.
    @ViewBuilder private var uiTestMultiFileDropTarget: some View {
        #if DEBUG
            if CommandLine.arguments.contains("-show-multi-file-drop-target") {
                VStack(spacing: GanchoTokens.Spacing.xxs) {
                    Image(systemName: "tray.and.arrow.down.fill")
                        .font(.title2)
                    Text(
                        verbatim: uiTestStartedFileCount == 0
                            ? "Drag files here"
                            : "\(uiTestStartedFileCount) file items"
                    )
                    .font(.caption.weight(.semibold))
                }
                .foregroundStyle(GanchoTokens.Palette.accent)
                .frame(width: 180, height: 76)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                .overlay {
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(
                            GanchoTokens.Palette.accent,
                            style: StrokeStyle(lineWidth: 2, dash: [6, 4]))
                }
                .padding(GanchoTokens.Spacing.lg)
                .onReceive(
                    NotificationCenter.default.publisher(for: .uiTestMultiFileDragPrepared)
                ) { notification in
                    uiTestPreparedFileCount = notification.object as? Int ?? 0
                }
                .onReceive(
                    NotificationCenter.default.publisher(for: .uiTestMultiFileDragStarted)
                ) { notification in
                    uiTestStartedFileCount = notification.object as? Int ?? 0
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    Text(
                        verbatim:
                            "Multi-file drag probe, prepared \(uiTestPreparedFileCount), pasteboard \(uiTestStartedFileCount)"
                    )
                )
                .accessibilityIdentifier("multi-file-drop-target")
            }
        #endif
    }

    @ViewBuilder private var telemetryConsentPrompt: some View {
        if model.isTelemetryConsentPromptPresented {
            VStack(alignment: .leading, spacing: GanchoTokens.Spacing.md) {
                Label("Help improve Gancho?", systemImage: "chart.bar.xaxis")
                    .font(.headline)
                Text(
                    // swiftlint:disable:next line_length
                    "Gancho can share anonymous feature counts and broad performance buckets. It never sends clipboard content, titles, searches, or source-app names."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                HStack {
                    Button("Keep disabled") {
                        model.setTelemetryConsent(.disabled)
                    }
                    Button("Allow anonymous diagnostics") {
                        model.setTelemetryConsent(.enabled)
                    }
                }
                .buttonStyle(.bordered)
            }
            .padding(GanchoTokens.Spacing.lg)
            .frame(width: 440)
            .ganchoSurface(radius: GanchoTokens.Radius.lg)
            .shadow(radius: 18, y: 8)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("telemetry-consent-prompt")
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
        }
    }

    /// The history list: search, one toolbar (boards · types · apps · save
    /// filter), the situational banners, and the rows. The peek lives in a
    /// sibling column (see `body`).
    private var listColumn: some View {
        @Bindable var search = search
        return VStack(spacing: 0) {
            SearchField("Search your clipboard", text: $search.query, style: .bare)
                .focused($focus, equals: .search)
                .onKeyPress(.downArrow, phases: [.down, .repeat]) { press in
                    if railFocus == nil, press.modifiers.contains(.shift),
                        !press.modifiers.contains(.command)
                    {
                        return extendSelection(by: 1)
                    }
                    return press.modifiers.contains(.command)
                        ? recallSearch(.newer) : handleNav(.down)
                }
                .onKeyPress(.upArrow, phases: [.down, .repeat]) { press in
                    // Plain ↑↓ navigate the list (and must keep key-repeat);
                    // ⌘↑/⌘↓ cycle recent searches, shell-style.
                    if railFocus == nil, press.modifiers.contains(.shift),
                        !press.modifiers.contains(.command)
                    {
                        return extendSelection(by: -1)
                    }
                    return press.modifiers.contains(.command)
                        ? recallSearch(.older) : handleNav(.up)
                }
                .onKeyPress(.leftArrow) { handleNav(.left) }
                .onKeyPress(.rightArrow) { handleNav(.right) }
                .onKeyPress(.space, phases: .down) { _ in
                    // In a rail, Space toggles the focused chip (and won't type a
                    // space); in the list it falls through to the search field.
                    guard railFocus != nil else { return .ignored }
                    return handleNav(.toggle)
                }
                .onKeyPress(.return, phases: .down) { press in
                    // In a rail, Enter toggles the focused chip. ⌥⌘Return enqueues
                    // the selection onto the paste stack. Otherwise an exact
                    // keyword match takes Enter (you typed the snippet shortcut on
                    // purpose); else Enter pastes the selection (⌥Return = plain).
                    if railFocus != nil { return handleNav(.toggle) }
                    if press.modifiers.contains(.command), press.modifiers.contains(.option),
                        !search.selectedItems.isEmpty
                    {
                        model.pushToStack(search.selectedItems)
                        return .handled
                    }
                    if let match = search.snippetMatch {
                        invokeSnippet(match)
                    } else {
                        pasteSelected(plain: press.modifiers.contains(.option))
                    }
                    return .handled
                }
                .onKeyPress(.escape) {
                    // The cheat-sheet intercepts esc first; otherwise esc hides
                    // the panel.
                    if showShortcuts {
                        showShortcuts = false
                        return .handled
                    }
                    model.panel.hide()
                    return .handled
                }
                .onKeyPress(characters: CharacterSet(charactersIn: "/"), phases: .down) { press in
                    // ⌘/ — the universal "show me the shortcuts" gesture.
                    guard press.modifiers.contains(.command) else { return .ignored }
                    showShortcuts.toggle()
                    return .handled
                }
                .onKeyPress(characters: CharacterSet(charactersIn: "a"), phases: .down) { press in
                    // ⌘A select-all: a menu-bar agent has no Edit menu to bind it,
                    // so route selectAll: down the responder chain to the field.
                    guard press.modifiers.contains(.command) else { return .ignored }
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                    return .handled
                }
                .onKeyPress(characters: .decimalDigits, phases: .down) { press in
                    guard press.modifiers.contains(.command),
                        let digit = Int(press.characters), (1...9).contains(digit),
                        search.filtered.indices.contains(digit - 1)
                    else { return .ignored }
                    model.paste(search.filtered[digit - 1])
                    return .handled
                }
                .onKeyPress(characters: CharacterSet(charactersIn: "p"), phases: .down) { press in
                    guard press.modifiers.contains(.command), let item = search.selectedItem else {
                        return .ignored
                    }
                    model.togglePin(item)
                    return .handled
                }
                .onKeyPress(characters: CharacterSet(charactersIn: "s"), phases: .down) { press in
                    guard press.modifiers.contains(.command), let item = search.selectedItem else {
                        return .ignored
                    }
                    model.promoteToSnippet(item)
                    return .handled
                }
                .onKeyPress(characters: CharacterSet(charactersIn: "bB"), phases: .down) { press in
                    // ⌘B opens the board picker for the selection; ⇧⌘B repeats
                    // the last board (curate many clips into one board fast).
                    guard press.modifiers.contains(.command), !search.selectedItems.isEmpty else {
                        return .ignored
                    }
                    if press.modifiers.contains(.shift) {
                        model.assignToLastBoard(search.selectedItems)
                    } else {
                        showBoardPicker = true
                    }
                    return .handled
                }

            Divider()
            panelToolbar
            Divider()

            VStack(spacing: GanchoTokens.Spacing.xs) {
                selectionContextBar

                if let notice = capturePresentation.notice {
                    PanelCaptureNoticeView(notice: notice, perform: handleCaptureAction)
                }

                if let snippetMatch = search.snippetMatch {
                    snippetBanner(snippetMatch)
                }

                if model.askAvailable, !search.query.isEmpty {
                    askRow
                }

                PanelResultsView(
                    query: search.query,
                    hasActiveFilter: search.hasActiveFilter,
                    firstRunHint: firstRunCaptureHint,
                    isGroupedView: search.isGroupedView,
                    groups: search.groups,
                    items: search.filtered,
                    selectedID: search.selectedItem?.id,
                    clearFilters: {
                        search.kindFilter = .all
                        search.selectedBoardID = nil
                        search.selectedSourceAppBundleID = nil
                    },
                    row: { item in clipRow(item: item) })
            }
            .padding(.top, GanchoTokens.Spacing.xxs)
        }
    }

    /// Boards on the left (their own scroll rail), type filters and the source
    /// app on the right, Save filter at the edge. Compact widths wrap the
    /// controls below the boards rather than clipping them. Keyboard order
    /// stays the same in either layout.
    private var panelToolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: GanchoTokens.Spacing.xs) {
                boardRail.frame(minWidth: 100)
                Rectangle().fill(.separator).frame(width: 1, height: 14)
                toolbarFilters
            }
            VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
                boardRail
                toolbarFilters
            }
        }
        .padding(.horizontal, GanchoTokens.Spacing.sm)
        .padding(.vertical, 6)
    }

    private var toolbarFilters: some View {
        HStack(spacing: GanchoTokens.Spacing.xs) {
            filterRail
            if !search.sourceApps.isEmpty {
                sourceAppMenu
            }
            Button {
                filterDraft = search.savedRule(named: "")
            } label: {
                Image(systemName: "line.3.horizontal.decrease.circle")
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 24, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Save filter")
            .disabled(model.fullStore == nil)
            .accessibilityLabel(Text("Save filter"))
            .accessibilityIdentifier("filter-save")
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    /// Sync state, capture state and the shortcut hints, under BOTH panes.
    private var statusFooter: some View {
        PanelStatusFooter(
            syncStatus: model.syncStatus,
            capture: capturePresentation,
            showKeyboardShortcuts: { showShortcuts.toggle() })
    }

    /// The type filters: All / Links / Code / Colors / Images / Secrets as
    /// glyph chips; the active one expands to its name.
    private var filterRail: some View {
        HStack(spacing: GanchoTokens.Spacing.xxs) {
            ForEach(ClipKindFilter.allCases) { filter in
                filterChip(filter)
            }
        }
        // The board rail beside it is a greedy ScrollView; without a fixed
        // size the HStack squeezes the active chip's name down to nothing.
        .fixedSize()
        // A plain stack is not an accessibility container: without this the
        // rail's id would replace every chip's own `filter-*` id.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("filter-rail")
    }

    /// Appears only for a batch, keeping single-selection navigation visually
    /// unchanged while making the available group operations explicit.
    @ViewBuilder private var selectionContextBar: some View {
        if search.selectionCount > 1 {
            PanelSelectionContextBar(
                selectionCount: search.selectionCount,
                copyCombined: {
                    combinedSelection = CombinedTextSelection(ids: search.selectedItems.map(\.id))
                },
                addToStack: { model.pushToStack(search.selectedItems) },
                addToBoard: { showBoardPicker = true },
                delete: { model.delete(search.selectedItems) },
                clear: { search.clearSelection() }
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    /// Source-app filter: recent apps and content-free counts in one compact
    /// menu, intersected with the board, type, and text query owned by search.
    private var sourceAppMenu: some View {
        let selectedBundleID = search.selectedSourceAppBundleID
        return Menu {
            Button {
                search.selectedSourceAppBundleID = nil
            } label: {
                Label("All apps", systemImage: "square.grid.2x2")
            }
            .accessibilityIdentifier("source-app-all")
            Divider()
            ForEach(search.sourceApps) { app in
                Button {
                    search.selectedSourceAppBundleID = app.bundleID
                } label: {
                    HStack {
                        Text(verbatim: SourceApp.displayName(forBundleID: app.bundleID))
                        Spacer()
                        Text(verbatim: "\(app.clipCount)")
                        if selectedBundleID == app.bundleID {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .accessibilityIdentifier("source-app-\(app.bundleID)")
            }
        } label: {
            railChipLabel(
                selectedBundleID.map { Text(verbatim: SourceApp.displayName(forBundleID: $0)) }
                    ?? Text("All apps"),
                isActive: selectedBundleID != nil, isFocused: false,
                showsTitle: selectedBundleID != nil
            ) {
                if let bundleID = selectedBundleID, let icon = SourceApp.icon(forBundleID: bundleID)
                {
                    Image(nsImage: icon).resizable().frame(width: 12, height: 12)
                } else {
                    Image(systemName: "app.dashed")
                }
            }
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(
            selectedBundleID.map { Text(verbatim: SourceApp.displayName(forBundleID: $0)) }
                ?? Text("Filter by app")
        )
        .accessibilityLabel(Text("Filter by app"))
        .accessibilityValue(
            selectedBundleID.map { Text(verbatim: SourceApp.displayName(forBundleID: $0)) }
                ?? Text("All apps")
        )
        .accessibilityIdentifier("source-app-filter")
    }

    private func filterChip(_ filter: ClipKindFilter) -> some View {
        let isActive = filter == search.kindFilter
        let index = ClipKindFilter.allCases.firstIndex(of: filter) ?? -1
        let tint = filter.tintKind.map(GanchoTokens.Palette.kindTint(for:))
        return railChip(
            Text(filter.title), isActive: isActive, isFocused: railFocus == .filters(index),
            identifier: "filter-\(filter.rawValue)"
        ) {
            Image(systemName: filter.symbolName)
                .foregroundStyle(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
        } action: {
            search.kindFilter = filter
            search.selectedIndex = 0
        }
    }

    /// A toolbar chip: glyph only at rest, checkmark + name when active, so the
    /// active one reads without relying on the accent colour alone (WCAG 1.4.1).
    private func railChip<Icon: View>(
        _ title: Text, isActive: Bool, isFocused: Bool, identifier: String,
        @ViewBuilder icon: () -> Icon, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            railChipLabel(title, isActive: isActive, isFocused: isFocused, showsTitle: isActive) {
                if isActive {
                    Image(systemName: "checkmark")
                } else {
                    icon()
                }
            }
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityIdentifier(identifier)
        .accessibilityValue(isActive ? Text("Selected") : Text("Not selected"))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    private func railChipLabel<Icon: View>(
        _ title: Text, isActive: Bool, isFocused: Bool, showsTitle: Bool,
        @ViewBuilder icon: () -> Icon
    ) -> some View {
        HStack(spacing: 5) {
            icon()
                .font(.caption.weight(.semibold))
                .frame(width: 12, height: 12)
            if showsTitle {
                // Truncate rather than widen the fixed-size toolbar; `.help` has the full name.
                title.font(.caption.weight(isActive ? .semibold : .medium)).lineLimit(1)
                    .frame(maxWidth: 120)
            }
        }
        .padding(.horizontal, showsTitle ? GanchoTokens.Spacing.xs : 6)
        .padding(.vertical, 4)
        .background(
            isActive ? AnyShapeStyle(GanchoTokens.Palette.accent) : AnyShapeStyle(.quaternary),
            in: Capsule()
        )
        .foregroundStyle(isActive ? AnyShapeStyle(Color.white) : AnyShapeStyle(.secondary))
        .overlay(railRing(isFocused))
        .contentShape(Capsule())
    }

    /// The keyboard-focus ring for a rail chip (filters + boards). A 1.5pt
    /// primary outline reads on both the quaternary and accent-filled chips,
    /// distinct from the accent fill that marks the *active* one.
    private func railRing(_ focused: Bool) -> some View {
        Capsule()
            .strokeBorder(
                focused ? AnyShapeStyle(.primary) : AnyShapeStyle(.clear), lineWidth: 1.5)
    }

    /// The boards: All clips · Favorites · user boards · New board. System
    /// boards are glyph-only until active; user boards always show their name
    /// (a bare colour dot would not identify them).
    private var boardRail: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: GanchoTokens.Spacing.xxs) {
                    railChip(
                        Text("All clips"), isActive: search.selectedBoardID == nil,
                        isFocused: railFocus == .boards(0), identifier: "board-all"
                    ) {
                        Image(systemName: "tray.full")
                    } action: {
                        search.selectedBoardID = nil
                    }
                    .id(Self.allClipsRailID)
                    ForEach(Array(model.boards.enumerated()), id: \.element.id) { index, board in
                        boardChip(board, index: index)
                    }
                    Button {
                        boardNameField = ""
                        boardSheet = .new
                    } label: {
                        railChipLabel(
                            Text("New board…"), isActive: false, isFocused: false, showsTitle: false
                        ) {
                            Image(systemName: "plus")
                        }
                    }
                    .buttonStyle(.plain)
                    .help("New board…")
                    .accessibilityLabel(Text("New board…"))
                    .accessibilityIdentifier("board-new")
                }
                .padding(.vertical, 1)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("board-rail")
            .onChange(of: railFocus) { _, focused in
                guard case .boards(let index) = focused else { return }
                if index == 0 {
                    proxy.scrollTo(Self.allClipsRailID)
                } else if model.boards.indices.contains(index - 1) {
                    proxy.scrollTo(model.boards[index - 1].id)
                }
            }
        }
    }

    private static let allClipsRailID = "board-all"

    private func boardChip(_ board: Pinboard, index: Int) -> some View {
        let isActive = search.selectedBoardID == board.id
        let title = board.isSystem ? Text("Favorites") : Text(verbatim: board.name)
        return Button {
            search.selectedBoardID = board.id
        } label: {
            railChipLabel(
                title, isActive: isActive, isFocused: railFocus == .boards(index + 1),
                showsTitle: isActive || !board.isSystem
            ) {
                if isActive {
                    Image(systemName: "checkmark")
                } else {
                    BoardIdentityMark(board: board, size: 11)
                }
            }
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityIdentifier("board-\(board.id.uuidString)")
        .accessibilityValue(isActive ? Text("Selected") : Text("Not selected"))
        .accessibilityAddTraits(isActive ? .isSelected : [])
        .contextMenu {
            if !board.isSystem {
                Button("Customize board…") {
                    // Context-menu views can outlive an async model refresh.
                    // Resolve the latest value by id so a second edit starts
                    // from the durable metadata, not the old menu's snapshot.
                    let current = model.boards.first { $0.id == board.id } ?? board
                    presentedSheet = .boardAppearance(current)
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
        switch boardSheet {
        case .new:
            Task { await model.createBoard(named: name) }
        case .newForClip(let clip):
            Task { await model.createBoard(named: name, assigning: clip) }
        case .rename(let board): Task { await model.renameBoard(board, name: name) }
        case nil: break
        }
        boardSheet = nil
    }

    /// "RECENT … N CLIPS" header above the list.
    /// "Ask your clipboard": a one-tap button to answer the typed query from
    /// history, the spinner while it runs, and the grounded answer card.
    @ViewBuilder private var askRow: some View {
        if isAsking {
            Label("Thinking…", systemImage: "sparkles")
                .font(.caption).foregroundStyle(.secondary)
                .symbolEffect(.pulse, options: .repeating)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, GanchoTokens.Spacing.xs)
        } else if let answer {
            answerCard(answer)
        } else {
            Button {
                runAsk()
            } label: {
                Label("Ask gancho", systemImage: "sparkles")
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, GanchoTokens.Spacing.sm)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        GanchoTokens.Palette.accent.opacity(0.12),
                        in: RoundedRectangle(
                            cornerRadius: GanchoTokens.Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, GanchoTokens.Spacing.xxs)
            .accessibilityIdentifier("ask-clipboard")
        }
    }

    private func answerCard(_ answer: AppModel.ClipboardAnswer) -> some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xxs) {
            HStack {
                Label("Answer", systemImage: "sparkles").font(.caption.weight(.semibold))
                Spacer()
                Button {
                    self.answer = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain).foregroundStyle(.tertiary)
                .accessibilityLabel(Text("Dismiss"))
            }
            ScrollView {
                Text(answer.answer)
                    .font(.callout)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 120)
            if !answer.sources.isEmpty {
                Text("Sources").font(.caption2).foregroundStyle(.secondary)
                ForEach(answer.sources.prefix(4)) { clip in
                    Button {
                        model.paste(clip)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: clip.kind.symbolName)
                                .font(.caption2)
                                .foregroundStyle(GanchoTokens.Palette.kindTint(for: clip.kind))
                            Text(clip.preview).font(.caption).lineLimit(1)
                        }
                    }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                }
            }
        }
        .padding(GanchoTokens.Spacing.sm)
        .background(
            GanchoTokens.Palette.accent.opacity(0.1),
            in: RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
        )
        .padding(.horizontal, GanchoTokens.Spacing.xxs)
    }

    private func runAsk() {
        let question = search.query
        askTask?.cancel()
        answer = nil
        isAsking = true
        askTask = Task { @MainActor in
            let result = await model.askClipboard(question)
            guard !Task.isCancelled, search.query == question else { return }
            isAsking = false
            answer = result
            askTask = nil
        }
    }

    /// One clip row with its shared interactions — used by both the flat
    /// (search/board) and date-grouped (recent) layouts.
    private func clipRow(item: ClipItem) -> some View {
        row(for: item)
            .id(item.id)
            // Every row is a drag source into other apps.
            // Sensitive clips are excluded inside the modifier.
            .clipDragSource(
                item,
                selectedItems: search.selectedItems,
                select: { toggling in select(item, toggling: toggling) },
                doubleClick: { model.paste(item) }
            )
            // Load this image's thumbnail once it scrolls into view (LazyVStack
            // builds only visible rows — the view-level virtual scrolling).
            .task(id: item.id) { await model.thumbnails.ensureLoaded(item) }
            // Pull the next page when this row is near the end (infinite scroll).
            .onAppear {
                guard let index = search.visibleIndex(of: item.id) else { return }
                Task { await search.loadMoreIfNeeded(index) }
            }
            // Single click SELECTS, double-click PASTES; hover no longer moves
            // the selection (arrows + click only). The select tap is a
            // `simultaneousGesture` so it fires on the FIRST click without waiting
            // to see whether a double-click follows — a plain `.onTapGesture`
            // beside `count: 2` makes SwiftUI delay every single click to
            // disambiguate, which is what made selection feel laggy.
            .onTapGesture(count: 2) { model.paste(item) }
            .simultaneousGesture(
                TapGesture().onEnded {
                    select(item, toggling: NSEvent.modifierFlags.contains(.command))
                }
            )
            .contextMenu { contextMenu(for: item) }
    }

    // MARK: - Keyboard cheat-sheet

    /// A dimmed scrim + a card listing every panel shortcut. Toggled by ⌘/ or
    /// the footer "?"; esc and a scrim tap dismiss it.
    @ViewBuilder private var boardPickerOverlay: some View {
        if showBoardPicker, !search.selectedItems.isEmpty {
            PanelBoardPicker(items: search.selectedItems) { showBoardPicker = false }
                .transition(.opacity)
        }
    }

    // MARK: - Capture notice

    /// Resolves the platform monitor into the pure, tested product policy used
    /// by both the capture banner and footer indicator.
    private var capturePresentation: PanelCapturePresentation {
        #if DEBUG
            // Privacy-safe marketing evidence uses a deliberately in-memory,
            // synthetic store. Suppress only that expected warning for the
            // dedicated screenshot flow; production builds ignore the flag.
            let suppressExpectedEphemeralNotice =
                CommandLine.arguments.contains("-suppress-storage-notice-for-ui-test")
        #else
            let suppressExpectedEphemeralNotice = false
        #endif
        return PanelCapturePresentation.resolve(
            storageIsEphemeral: model.storageIsEphemeral,
            suppressExpectedEphemeralNotice: suppressExpectedEphemeralNotice,
            privateModeEnabled: model.preferences.isPrivateModePaused,
            runtimeStatus: model.monitorStatus.panelCaptureRuntimeStatus)
    }

    private func handleCaptureAction(_ action: PanelCaptureAction) {
        switch action {
        case .resumePrivateMode: model.togglePrivateMode()
        case .resumeCapture: model.togglePause()
        case .openPermissionSettings: model.permissionWindow.show(model: model)
        }
    }

    /// The first-run empty-state hint. Normally "⌘C to start", but when capture
    /// is actually blocked it names the cause instead of misleading the user into
    /// thinking a copy will land (the banner above offers the one-tap fix).
    private var firstRunCaptureHint: LocalizedStringKey {
        switch capturePresentation.notice {
        case .privateMode: "Private Mode is on — resume it above to start saving."
        case .denied: "Clipboard access is off — turn it on above to start."
        case .screenShare: "Capture is paused while sharing your screen."
        case .paused: "Capture is paused — resume it above to start saving."
        default: "⌘C in any app to start"
        }
    }

    private func row(for item: ClipItem) -> some View {
        let index = search.visibleIndex(of: item.id)
        // ClipCard is the design's ClipRow: kind glyph (or colour swatch),
        // title/preview, pin / Universal-Clipboard markers, and the ⌘N
        // quick-paste badge for the first nine rows.
        return ClipCard(
            item: item, isSelected: search.isSelected(item.id),
            previewsHidden: model.preferences.isPrivateModePaused,
            shortcutNumber: index.flatMap { $0 < 9 ? $0 + 1 : nil },
            thumbnail: model.thumbnails.cached(for: item.id),
            // Only the anchor claims the gliding highlight: two rows sharing one
            // matched id (a ⇧ range) would log and draw nothing.
            selectionNamespace: selectionNamespace,
            isSelectionAnchor: search.selectedItem?.id == item.id)
    }

    /// Pin/board assignment — the context-menu path; drag & drop arrives
    /// with the panel's Quick Look evolution.
    @ViewBuilder
    private func contextMenu(for item: ClipItem) -> some View {
        if model.canCopyImageText(item) {
            Button("Copy text from image") {
                // Land the result in the peek when this row can be selected;
                // otherwise fall back to the detached toast flow — never silence.
                if let index = search.filtered.firstIndex(where: { $0.id == item.id }) {
                    select(index)
                }
                let surface: AppModel.ManualOCRSurface =
                    search.selectedItem?.id == item.id ? .peek : .detached
                model.copyImageText(item, surface: surface)
            }
            .accessibilityIdentifier("image-copy-text")
        }
        Button(item.isPinned ? "Unpin" : "Pin") {
            model.togglePin(item)
        }
        Button("Save as snippet") {
            model.promoteToSnippet(item)
        }
        Button("Add to paste stack") {
            model.pushToStack(item)
        }
        Menu("Paste as") {
            ForEach(PasteTransform.allCases, id: \.self) { transform in
                Button(LocalizedStringKey(transform.title)) {
                    model.paste(item, transform: transform)
                }
            }
        }
        Menu("Add to board") {
            ForEach(model.boards) { board in
                Button(board.name) { model.assign(item, toBoard: board) }
            }
            Divider()
            Button("New board…") {
                boardNameField = ""
                boardSheet = .newForClip(item)
            }
            Button("Remove from board") { model.removeFromAllBoards(item) }
        }
        Button("Delete", role: .destructive) {
            model.delete(item)
        }
    }

    private func pasteSelected(plain: Bool) {
        guard let item = search.selectedItem else { return }
        model.paste(item, asPlainText: plain)
    }

    /// Resolves a clicked row against the current list; a row that already
    /// left it (mid-refresh) is ignored.
    private func select(_ item: ClipItem, toggling: Bool) {
        guard let index = search.visibleIndex(of: item.id) else { return }
        select(index, toggling: toggling)
    }

    /// Select a row without acting on it (the click + arrow path). Re-grabs
    /// search focus so type-to-search and Enter-to-paste keep working after a
    /// click lands focus on the row.
    private func select(_ index: Int, toggling: Bool = false) {
        search.select(index, toggling: toggling)
        railFocus = nil
        focus = .search
    }

    private func extendSelection(by delta: Int) -> KeyPress.Result {
        search.moveSelection(by: delta, extending: true)
        if delta > 0 { Task { await search.loadMoreIfNeeded(search.selectedIndex) } }
        focus = .search
        return .handled
    }

    // MARK: - Rail keyboard navigation (filters + boards above the list)

    /// Which way ⌘↑/⌘↓ walk the recall list (newest first: older = deeper).
    private enum RecallStep { case older, newer }

    /// Shell-style recall of remembered searches. First ⌘↑ loads the
    /// list and applies the newest; further ⌘↑ walk older; ⌘↓ walks back and,
    /// past the newest, clears the field and ends the session. Plain ↑↓ are
    /// untouched — they navigate the list.
    private func recallSearch(_ step: RecallStep) -> KeyPress.Result {
        if searchHistory.isEmpty {
            guard step == .older else { return .handled }
            Task { @MainActor in
                searchHistory = await model.recentSearches()
                applyRecall(at: 0)
            }
            return .handled
        }
        switch step {
        case .older: applyRecall(at: (historyCursor ?? -1) + 1)
        case .newer: applyRecall(at: (historyCursor ?? 0) - 1)
        }
        return .handled
    }

    private func applyRecall(at index: Int) {
        guard !searchHistory.isEmpty else { return }
        guard index >= 0 else {
            // Walked past the newest entry: back to an empty field.
            historyCursor = nil
            recalledQuery = ""
            search.query = ""
            return
        }
        let clamped = min(index, searchHistory.count - 1)
        historyCursor = clamped
        recalledQuery = searchHistory[clamped]
        search.query = searchHistory[clamped]
    }

    /// Resolve an arrow / Space / Enter keypress through the pure
    /// `PanelNavigation` reducer, then apply the next state back onto the search
    /// model + view and run the two effects the reducer can't be pure about:
    /// moving SwiftUI focus into the peek, and pulling the next page. Returns
    /// `.ignored` only when the reducer did not consume the key.
    private func handleNav(_ key: PanelNavigationKey) -> KeyPress.Result {
        let context = PanelNavigationContext(
            rowCount: search.filtered.count,
            boardIDs: model.boards.map(\.id),
            hasSelection: search.selectedItem != nil)
        let state = PanelNavigationState(
            railFocus: railFocus,
            selectedIndex: search.selectedIndex,
            kindFilter: search.kindFilter,
            selectedBoardID: search.selectedBoardID)
        let result = PanelNavigation.reduce(key, state: state, context: context)
        // Write back only what changed — avoids spurious `@State`/`@Observable`
        // invalidations (and a no-op `onChange`) on a plain arrow keypress.
        if railFocus != result.state.railFocus { railFocus = result.state.railFocus }
        if search.selectedIndex != result.state.selectedIndex {
            search.selectedIndex = result.state.selectedIndex
        }
        if search.kindFilter != result.state.kindFilter {
            search.kindFilter = result.state.kindFilter
        }
        if search.selectedBoardID != result.state.selectedBoardID {
            search.selectedBoardID = result.state.selectedBoardID
        }
        if result.focusPeek { focus = .peek }
        if let index = result.loadMoreAt { Task { await search.loadMoreIfNeeded(index) } }
        return result.handled ? .handled : .ignored
    }

    /// The keyword-match banner above the list: ⏎ inserts the snippet (a
    /// template opens the fill sheet first). Tinted with the accent to read as
    /// the primary action when present.
    private func snippetBanner(_ snippet: ClipItem) -> some View {
        Button {
            invokeSnippet(snippet)
        } label: {
            HStack(spacing: GanchoTokens.Spacing.xs) {
                Image(systemName: "bolt.fill").font(.caption)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Insert snippet").font(.caption2).foregroundStyle(.secondary)
                    Text(snippet.title.isEmpty ? snippet.preview : snippet.title)
                        .font(.callout.weight(.semibold)).lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "return").font(.caption2).foregroundStyle(.secondary)
            }
            .padding(.horizontal, GanchoTokens.Spacing.sm)
            .padding(.vertical, GanchoTokens.Spacing.xs)
            .background(
                GanchoTokens.Palette.accent.opacity(0.14),
                in: RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, GanchoTokens.Spacing.xxs)
        .accessibilityIdentifier("snippet-insert-banner")
    }

    /// Invoke a snippet: fill its {fields} via a sheet if it's a template,
    /// otherwise paste straight away (incrementing its usage count).
    private func invokeSnippet(_ snippet: ClipItem) {
        Task {
            var body = ""
            if case .text(let text)? = try? await model.store.content(for: snippet.id) {
                body = text
            }
            let fields = SnippetTemplate.fields(in: body)
            if fields.isEmpty {
                model.pasteSnippet(snippet, values: [:])
            } else {
                presentedSheet = .snippet(
                    SnippetFillRequest(snippet: snippet, body: body, fields: fields))
            }
        }
    }
}

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

/// The panel has one native sheet presentation slot. Keeping snippet filling
/// and board appearance in one enum avoids the unreliable multiple-sheet state
/// that previously made presentations silently compete.
private enum PanelPresentedSheet: Identifiable {
    case snippet(SnippetFillRequest)
    case boardAppearance(Pinboard)

    var id: String {
        switch self {
        case .snippet(let request): "snippet-\(request.id.uuidString)"
        case .boardAppearance(let board): "board-appearance-\(board.id.uuidString)"
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
    @FocusState private var focus: PanelFocus?
    /// The search + list state (query, results, filters, selection, paging,
    /// grouping) — lifted into `PanelSearchModel` so it is `@Observable` and
    /// unit-testable; the view keeps presentation only.
    @State private var search: PanelSearchModel
    /// Non-nil when the keyboard moved up into the filter/board rails.
    @State private var railFocus: RailFocus?
    @State private var previewText = ""
    /// Identity of the clip whose full text produced `previewText`. Until it
    /// matches the current selection, the UI renders metadata-only preview text
    /// so an async read can never flash the previous clip's body.
    @State private var previewTextItemID: UUID?
    @State private var previewTextIsEditable = false
    @State private var boardSheet: BoardSheet?
    @State private var boardNameField = ""
    /// The board a destructive "Delete board" is awaiting confirmation on.
    @State private var boardPendingDeletion: Pinboard?
    @State private var presentedSheet: PanelPresentedSheet?
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

    init(model: AppModel, displayDefaults: UserDefaults = .standard) {
        _search = State(wrappedValue: PanelSearchModel(source: model))
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
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    var body: some View {
        let panelTextSize = PanelTextSize.resolved(panelTextSizeRaw)
        HStack(alignment: .top, spacing: GanchoTokens.Spacing.sm) {
            listColumn
                .frame(minWidth: 360, idealWidth: 440, maxWidth: .infinity)
            // The peek opens BESIDE the list (not a modal) and follows the
            // hovered / selected clip — Quick-Look-style.
            if let selected = search.selectedItem {
                let hasLoadedSelectedText = previewTextItemID == selected.id
                ClipPeek(
                    item: selected,
                    text: hasLoadedSelectedText ? previewText : selected.preview,
                    isTextEditable: hasLoadedSelectedText && previewTextIsEditable,
                    focus: $focus
                )
                // Drafts, async save callbacks, and action state belong to one
                // clip only. A new selection gets a fresh preview identity.
                .id(selected.id)
                .frame(minWidth: 320, idealWidth: 400, maxWidth: .infinity)
                .ganchoSurface(radius: GanchoTokens.Radius.lg)
                .transition(.opacity)
            }
        }
        .padding(GanchoTokens.Spacing.sm)
        .frame(minWidth: 720, minHeight: 460)
        .dynamicTypeSize(panelTextSize.dynamicTypeSize)
        .overlay { PanelShortcutsOverlay(isPresented: $showShortcuts) }
        .overlay { boardPickerOverlay }
        .overlay { telemetryConsentPrompt }
        .overlay(alignment: .top) { uiTestMultiFileDropTarget }
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
        .onChange(of: search.selectedBoardID) { _, _ in
            Task { await search.refresh() }
        }
        .onChange(of: search.selectedSourceAppBundleID) { _, _ in
            Task { await search.refresh() }
        }
        // The kind filter narrows client-side, so regroup without a re-query.
        .onChange(of: search.kindFilter) { _, _ in search.rebuildGroups() }
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
            Button("Delete board", role: .destructive) {
                if search.selectedBoardID == board.id { search.selectedBoardID = nil }
                model.deleteBoard(board)
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("Your clips stay in history — only the board is removed.")
        }
        .sheet(item: $presentedSheet) { sheet in
            switch sheet {
            case .snippet(let request):
                SnippetFillSheet(request: request) { values in
                    model.pasteSnippet(request.snippet, values: values)
                    presentedSheet = nil
                } onCancel: {
                    presentedSheet = nil
                }
            case .boardAppearance(let board):
                BoardIdentityEditor(board: board) { colorHex, emoji in
                    await model.updateBoardIdentity(
                        board, colorHex: colorHex, emoji: emoji)
                }
            }
        }
        // Load the peek for the selected clip, keyed on its id and debounced:
        // arrowing fast cancels the in-flight load, so only the clip you land on
        // is read and rendered — keeps navigation responsive.
        .task(id: search.selectedItem?.id) {
            try? await Task.sleep(for: .milliseconds(60))
            guard !Task.isCancelled else { return }
            await loadSelectedText()
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
            _ in
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

    /// The history list: search, rows, and the sync footer. The peek lives in a
    /// sibling column (see `body`).
    private var listColumn: some View {
        @Bindable var search = search
        return VStack(spacing: GanchoTokens.Spacing.xs) {
            SearchField("Search your clipboard", text: $search.query)
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

            boardRail

            filterRail

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

            if search.filtered.isEmpty {
                emptyState
            } else {
                // The chronological recent list groups under sticky date headers;
                // search (ranked) and a board (curated) keep a flat list under the
                // single "Recent" header.
                if !search.isGroupedView { recentHeader }
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(
                            spacing: GanchoTokens.Spacing.xxs,
                            pinnedViews: search.isGroupedView ? [.sectionHeaders] : []
                        ) {
                            if search.isGroupedView {
                                ForEach(search.groups) { group in
                                    Section {
                                        ForEach(group.rows, id: \.item.id) { entry in
                                            clipRow(index: entry.index, item: entry.item)
                                        }
                                    } header: {
                                        sectionHeader(group.section, count: group.rows.count)
                                    }
                                }
                            } else {
                                ForEach(Array(search.filtered.enumerated()), id: \.element.id) {
                                    index, item in
                                    clipRow(index: index, item: item)
                                }
                            }
                        }
                        .padding(.horizontal, GanchoTokens.Spacing.xxs)
                    }
                    .onChange(of: search.selectedIndex) { _, index in
                        guard search.filtered.indices.contains(index) else { return }
                        proxy.scrollTo(search.filtered[index].id)
                    }
                }
            }
            PanelStatusFooter(
                syncStatus: model.syncStatus,
                capture: capturePresentation,
                showKeyboardShortcuts: { showShortcuts.toggle() })
        }
        .ganchoSurface(radius: GanchoTokens.Radius.lg)
    }

    /// The design's type-filter rail: All / Links / Code / Colors / Images /
    /// Secrets, "All" active by default.
    private var filterRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: GanchoTokens.Spacing.xxs) {
                ForEach(ClipKindFilter.allCases) { filter in
                    filterPill(filter)
                }
                if !search.sourceApps.isEmpty {
                    sourceAppMenu
                }
            }
            .padding(.horizontal, GanchoTokens.Spacing.xxs)
        }
        .accessibilityIdentifier("filter-rail")
    }

    /// Appears only for a batch, keeping single-selection navigation visually
    /// unchanged while making the available group operations explicit.
    @ViewBuilder private var selectionContextBar: some View {
        if search.selectionCount > 1 {
            HStack(spacing: GanchoTokens.Spacing.sm) {
                Label("\(search.selectionCount) clips", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(GanchoTokens.Palette.accent)
                Spacer(minLength: 0)
                Button {
                    model.pushToStack(search.selectedItems)
                } label: {
                    Image(systemName: "square.stack.3d.up")
                }
                .help("Add to paste stack")
                .accessibilityLabel("Add to paste stack")
                .accessibilityIdentifier("selection-add-to-stack-button")

                Button {
                    showBoardPicker = true
                } label: {
                    Image(systemName: "square.stack")
                }
                .help("Add to board")
                .accessibilityLabel("Add to board")
                .accessibilityIdentifier("selection-add-to-board-button")

                Button(role: .destructive) {
                    model.delete(search.selectedItems)
                } label: {
                    Image(systemName: "trash")
                }
                .foregroundStyle(.red)
                .help("Delete")
                .accessibilityLabel("Delete")
                .accessibilityIdentifier("selection-delete-button")

                Divider().frame(height: 16)
                Button("Clear") { search.clearSelection() }
                    .accessibilityIdentifier("selection-clear-button")
            }
            .buttonStyle(.plain)
            .padding(.horizontal, GanchoTokens.Spacing.sm)
            .padding(.vertical, GanchoTokens.Spacing.xxs)
            .background(
                GanchoTokens.Palette.accent.opacity(0.08),
                in: RoundedRectangle(
                    cornerRadius: GanchoTokens.Radius.md, style: .continuous)
            )
            .padding(.horizontal, GanchoTokens.Spacing.xxs)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("\(search.selectionCount) clips"))
            .accessibilityIdentifier("selection-context-bar")
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    /// Source-app filter: recent apps and content-free counts in one compact
    /// menu, intersected with the board, type, and text query owned by search.
    private var sourceAppMenu: some View {
        Menu {
            Button {
                search.selectedSourceAppBundleID = nil
            } label: {
                Label("All apps", systemImage: "square.grid.2x2")
            }
            Divider()
            ForEach(search.sourceApps) { app in
                Button {
                    search.selectedSourceAppBundleID = app.bundleID
                } label: {
                    HStack {
                        Text(verbatim: SourceApp.displayName(forBundleID: app.bundleID))
                        Spacer()
                        Text(verbatim: "\(app.clipCount)")
                        if search.selectedSourceAppBundleID == app.bundleID {
                            Image(systemName: "checkmark")
                        }
                    }
                }
                .accessibilityIdentifier("source-app-\(app.bundleID)")
            }
        } label: {
            HStack(spacing: 4) {
                if let bundleID = search.selectedSourceAppBundleID,
                    let icon = SourceApp.icon(forBundleID: bundleID)
                {
                    Image(nsImage: icon).resizable().frame(width: 12, height: 12)
                } else {
                    Image(systemName: "app.dashed").font(.caption2)
                }
                if let bundleID = search.selectedSourceAppBundleID {
                    Text(verbatim: SourceApp.displayName(forBundleID: bundleID))
                } else {
                    Text("All apps")
                }
            }
            .font(.caption.weight(search.selectedSourceAppBundleID == nil ? .medium : .semibold))
            .padding(.horizontal, GanchoTokens.Spacing.xs)
            .padding(.vertical, 3)
            .background(
                search.selectedSourceAppBundleID == nil
                    ? AnyShapeStyle(.quaternary) : AnyShapeStyle(GanchoTokens.Palette.accent),
                in: Capsule()
            )
            .foregroundStyle(
                search.selectedSourceAppBundleID == nil
                    ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.white)
            )
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .accessibilityLabel(Text("Filter by app"))
        .accessibilityIdentifier("source-app-filter")
    }

    private func filterPill(_ filter: ClipKindFilter) -> some View {
        let isActive = filter == search.kindFilter
        let isFocused = railFocus == .filters(ClipKindFilter.allCases.firstIndex(of: filter) ?? -1)
        return Button {
            search.kindFilter = filter
            search.selectedIndex = 0
        } label: {
            HStack(spacing: 4) {
                // A checkmark marks the active pill so the selection reads
                // without relying on the accent colour alone (WCAG 1.4.1).
                if isActive {
                    Image(systemName: "checkmark").font(.caption2.weight(.bold))
                        .accessibilityHidden(true)
                } else if let kind = filter.tintKind {
                    Circle()
                        .fill(GanchoTokens.Palette.kindTint(for: kind))
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                }
                Text(filter.title).font(.caption.weight(isActive ? .semibold : .medium))
            }
            .padding(.horizontal, GanchoTokens.Spacing.xs)
            .padding(.vertical, 3)
            .background(
                isActive ? AnyShapeStyle(GanchoTokens.Palette.accent) : AnyShapeStyle(.quaternary),
                in: Capsule()
            )
            .foregroundStyle(isActive ? AnyShapeStyle(Color.white) : AnyShapeStyle(.secondary))
            .overlay(railRing(isFocused))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("filter-\(filter.rawValue)")
        .accessibilityValue(isActive ? Text("Selected") : Text("Not selected"))
        .accessibilityAddTraits(isActive ? .isSelected : [])
    }

    /// The keyboard-focus ring for a rail chip (filters + boards). A 1.5pt
    /// primary outline reads on both the quaternary and accent-filled chips,
    /// distinct from the accent fill that marks the *active* one.
    private func railRing(_ focused: Bool) -> some View {
        Capsule()
            .strokeBorder(
                focused ? AnyShapeStyle(.primary) : AnyShapeStyle(.clear), lineWidth: 1.5)
    }

    /// The board rail above the type filters: All clips · Favorites · user
    /// boards · + New board. The active board takes the system accent; the
    /// built-in Favorites board can't be renamed or deleted.
    private var boardRail: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: GanchoTokens.Spacing.xxs) {
                boardChip(
                    label: Text("All clips"), systemImage: "tray.full",
                    isActive: search.selectedBoardID == nil, isFocused: railFocus == .boards(0),
                    identifier: "board-all"
                ) {
                    search.selectedBoardID = nil
                }
                ForEach(Array(model.boards.enumerated()), id: \.element.id) { index, board in
                    boardChip(
                        label: board.isSystem ? Text("Favorites") : Text(verbatim: board.name),
                        systemImage: board.sfSymbol,
                        isActive: search.selectedBoardID == board.id,
                        isFocused: railFocus == .boards(index + 1),
                        identifier: "board-\(board.id.uuidString)",
                        board: board
                    ) {
                        search.selectedBoardID = board.id
                    }
                    .contextMenu {
                        if !board.isSystem {
                            Button("Customize board…") {
                                // Context-menu views can outlive an async model
                                // refresh. Resolve the latest value by id so a
                                // second edit starts from the durable metadata,
                                // not the snapshot captured by the old menu.
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
                Button {
                    boardNameField = ""
                    boardSheet = .new
                } label: {
                    Label("New board…", systemImage: "plus")
                        .font(.caption.weight(.medium))
                        .padding(.horizontal, GanchoTokens.Spacing.xs)
                        .padding(.vertical, 3)
                        .background(.quaternary, in: Capsule())
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("board-new")
            }
            .padding(.horizontal, GanchoTokens.Spacing.xxs)
            .frame(minHeight: 28)
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier("board-rail")
    }

    private func boardChip(
        label: Text, systemImage: String, isActive: Bool, isFocused: Bool, identifier: String,
        board: Pinboard? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                // Active board swaps its glyph for a checkmark, so the selection
                // shows without leaning on the accent colour alone (WCAG 1.4.1).
                if isActive {
                    Image(systemName: "checkmark").font(.caption2)
                        .accessibilityHidden(true)
                } else if let board {
                    BoardIdentityMark(board: board, size: 11)
                } else {
                    Image(systemName: systemImage).font(.caption2)
                        .accessibilityHidden(true)
                }
                label.font(.caption.weight(isActive ? .semibold : .medium))
            }
            .padding(.horizontal, GanchoTokens.Spacing.xs)
            .padding(.vertical, 3)
            .background(
                isActive ? AnyShapeStyle(GanchoTokens.Palette.accent) : AnyShapeStyle(.quaternary),
                in: Capsule()
            )
            .foregroundStyle(isActive ? AnyShapeStyle(Color.white) : AnyShapeStyle(.secondary))
            .overlay(railRing(isFocused))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
        .accessibilityValue(isActive ? Text("Selected") : Text("Not selected"))
        .accessibilityAddTraits(isActive ? .isSelected : [])
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
        case .rename(let board): model.renameBoard(board, name: name)
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

    private var recentHeader: some View {
        HStack {
            Text("Recent")
            Spacer()
            Text("\(search.filtered.count) clips")
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.tertiary)
        .textCase(.uppercase)
        .padding(.horizontal, GanchoTokens.Spacing.xs)
    }

    /// One clip row with its shared interactions — used by both the flat
    /// (search/board) and date-grouped (recent) layouts.
    private func clipRow(index: Int, item: ClipItem) -> some View {
        row(for: item, index: index)
            .id(item.id)
            // Every row is a drag source into other apps.
            // Sensitive clips are excluded inside the modifier.
            .clipDragSource(
                item,
                selectedItems: search.selectedItems,
                select: { toggling in select(index, toggling: toggling) },
                doubleClick: { model.paste(item) }
            )
            // Load this image's thumbnail once it scrolls into view (LazyVStack
            // builds only visible rows — the view-level virtual scrolling).
            .task(id: item.id) { await model.thumbnails.ensureLoaded(item) }
            // Pull the next page when this row is near the end (infinite scroll).
            .onAppear { Task { await search.loadMoreIfNeeded(index) } }
            // Single click SELECTS, double-click PASTES; hover no longer moves
            // the selection (arrows + click only). The select tap is a
            // `simultaneousGesture` so it fires on the FIRST click without waiting
            // to see whether a double-click follows — a plain `.onTapGesture`
            // beside `count: 2` makes SwiftUI delay every single click to
            // disambiguate, which is what made selection feel laggy.
            .onTapGesture(count: 2) { model.paste(item) }
            .simultaneousGesture(
                TapGesture().onEnded {
                    select(index, toggling: NSEvent.modifierFlags.contains(.command))
                }
            )
            .contextMenu { contextMenu(for: item) }
    }

    /// A sticky section header — "Pinned" (with a pin glyph) or a semantic date
    /// (Today, Yesterday, This month, …) — with the section's clip count.
    private func sectionHeader(_ section: ClipSection, count: Int) -> some View {
        HStack(spacing: 4) {
            if section == .pinned {
                Image(systemName: "pin.fill").font(.system(size: 8))
            }
            Text(sectionTitle(section))
            Spacer()
            Text("\(count) clips")
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.tertiary)
        .textCase(.uppercase)
        .padding(.horizontal, GanchoTokens.Spacing.xs)
        .padding(.vertical, GanchoTokens.Spacing.xxs)
        .background(.ultraThinMaterial)
    }

    private func sectionTitle(_ section: ClipSection) -> LocalizedStringKey {
        switch section {
        case .pinned: "Pinned"
        case .date(let bucket): bucketTitle(bucket)
        }
    }

    private func bucketTitle(_ bucket: DateBucket) -> LocalizedStringKey {
        switch bucket {
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .thisMonth: "This month"
        case .lastMonth: "Last month"
        case .thisYear: "This year"
        case .lastYear: "Last year"
        case .older: "Older"
        }
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

    /// First-run and no-results states — warm and instructive, never a dead end
    /// (the design's empty-states spec). Branches on whether a query is active.
    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: GanchoTokens.Spacing.xs) {
            if search.query.isEmpty {
                Image(systemName: "doc.on.clipboard.fill")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(
                        GanchoTokens.Palette.success.gradient,
                        in: RoundedRectangle(
                            cornerRadius: GanchoTokens.Radius.xl, style: .continuous)
                    )
                    .padding(.bottom, GanchoTokens.Spacing.xs)
                Text("Your history starts here")
                    .font(.headline)
                Text(
                    "Copy anything — text, a link, an image — and it appears here, ready to paste again."
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                Text(firstRunCaptureHint)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, GanchoTokens.Spacing.xxs)
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(.secondary)
                    .frame(width: 64, height: 64)
                    .background(
                        .quaternary,
                        in: RoundedRectangle(
                            cornerRadius: GanchoTokens.Radius.xl, style: .continuous)
                    )
                    .padding(.bottom, GanchoTokens.Spacing.xs)
                Text("No matches")
                    .font(.headline)
                Text("No clips for “\(search.query)”.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if search.hasActiveFilter {
                    // esc hides the panel, so the old "press esc" hint was wrong;
                    // a real button clears the type/board filter narrowing the list.
                    Button("Clear filters") {
                        search.kindFilter = .all
                        search.selectedBoardID = nil
                        search.selectedSourceAppBundleID = nil
                    }
                    .buttonStyle(.borderless)
                    .padding(.top, GanchoTokens.Spacing.xxs)
                    .accessibilityIdentifier("clear-filters")
                } else {
                    Text("Try another word.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .padding(.top, GanchoTokens.Spacing.xxs)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, GanchoTokens.Spacing.lg)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(
            search.query.isEmpty ? "panel-empty-firstrun" : "panel-empty-noresults")
    }

    private func row(for item: ClipItem, index: Int) -> some View {
        // ClipCard is the design's ClipRow: kind glyph (or colour swatch),
        // title/preview, pin / Universal-Clipboard markers, and the ⌘N
        // quick-paste badge for the first nine rows.
        ClipCard(
            item: item, isSelected: search.isSelected(item.id),
            previewsHidden: model.preferences.isPrivateModePaused,
            shortcutNumber: index < 9 ? index + 1 : nil,
            thumbnail: model.thumbnails.cached(for: item.id))
    }

    /// Pin/board assignment — the context-menu path; drag & drop arrives
    /// with the panel's Quick Look evolution.
    @ViewBuilder
    private func contextMenu(for item: ClipItem) -> some View {
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

    /// Load the selected clip's full text for the peek beside the list. Only
    /// text-like clips need a content read; reading an image/file blob from
    /// disk on every selection change would lag navigation, so those fall back
    /// to the cheap stored preview.
    private func loadSelectedText() async {
        guard let item = search.selectedItem else {
            previewText = ""
            previewTextItemID = nil
            previewTextIsEditable = false
            return
        }
        previewText =
            ClipSafePresentation.requiresMasking(item)
            ? ClipSafePresentation.masked : item.preview
        previewTextItemID = item.id
        previewTextIsEditable = false
        guard item.kind != .image, item.kind != .fileReference else {
            return
        }
        let store = model.store
        let payload = await ClipPreviewLoader().load(item) { id in
            try await store.content(for: id)
        }
        guard !Task.isCancelled, search.selectedItem?.id == item.id else { return }
        switch payload {
        case .masked(let text), .text(let text):
            previewText = text
            previewTextIsEditable =
                !ClipSafePresentation.requiresMasking(item) && item.kind.allowsTextEditing
        case .binary, .fileReferences, .unavailable:
            break
        }
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

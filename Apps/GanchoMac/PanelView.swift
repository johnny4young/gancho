import AppKit
import ClipboardCore
import Combine
import GanchoAI
import GanchoAppCore
import GanchoDesign
import GanchoKit
import SwiftUI

// PanelView is the main keyboard-first interaction surface; splitting it needs
// a focused UI refactor so the current behavior stays reviewable in this PR.
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

// PanelView owns the coordinated search, rails, peek, and sheet state today;
// keep the size exception local until those responsibilities are split.
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

    init(model: AppModel) {
        _search = State(wrappedValue: PanelSearchModel(source: model))
    }

    /// Zero-size buttons that claim ⌘V / ⌥⌘V as keyboard shortcuts. The search
    /// field is the first responder for type-to-search, so a plain key handler
    /// never sees ⌘V — the field editor consumes it as native "paste" and dumps
    /// the clipboard into the query. A keyboardShortcut is resolved as a command
    /// (ahead of the field editor), so ⌘V pastes the SELECTED clip like Enter.
    private var pasteShortcutButtons: some View {
        Group {
            Button("") { if let item = search.selectedItem { model.paste(item) } }
                .keyboardShortcut("v", modifiers: .command)
            Button("") {
                if let item = search.selectedItem { model.paste(item, asPlainText: true) }
            }
            .keyboardShortcut("v", modifiers: [.command, .option])
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    var body: some View {
        HStack(alignment: .top, spacing: GanchoTokens.Spacing.sm) {
            listColumn
                .frame(width: 440)
            // The peek opens BESIDE the list (not a modal) and follows the
            // hovered / selected clip — Quick-Look-style.
            if let selected = search.selectedItem {
                ClipPeek(item: selected, text: previewText, focus: $focus)
                    .frame(width: 400)
                    .ganchoSurface(radius: GanchoTokens.Radius.lg)
                    .transition(.opacity)
            }
        }
        .padding(GanchoTokens.Spacing.sm)
        .frame(minWidth: search.selectedItem == nil ? 472 : 864, minHeight: 520)
        .overlay { shortcutsOverlay }
        .overlay { boardPickerOverlay }
        .overlay { telemetryConsentPrompt }
        .background { pasteShortcutButtons }
        .animation(.snappy(duration: 0.12), value: showShortcuts)
        .task { await search.refresh() }
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
            Task { await search.refresh() }
        }
        .onChange(of: model.recentItems) { _, _ in
            Task { await search.refresh() }
        }
        .onChange(of: search.selectedBoardID) { _, _ in
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
                    press.modifiers.contains(.command) ? recallSearch(.newer) : handleNav(.down)
                }
                .onKeyPress(.upArrow, phases: [.down, .repeat]) { press in
                    // Plain ↑↓ navigate the list (and must keep key-repeat);
                    // ⌘↑/⌘↓ cycle recent searches, shell-style.
                    press.modifiers.contains(.command) ? recallSearch(.older) : handleNav(.up)
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
                        let item = search.selectedItem
                    {
                        model.pushToStack(item)
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
                    guard press.modifiers.contains(.command), let item = search.selectedItem else {
                        return .ignored
                    }
                    if press.modifiers.contains(.shift) {
                        model.assignToLastBoard(item)
                    } else {
                        showBoardPicker = true
                    }
                    return .handled
                }

            boardRail

            filterRail

            if let captureNotice {
                captureBanner(captureNotice)
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
            panelFooter
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
            }
            .padding(.horizontal, GanchoTokens.Spacing.xxs)
        }
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
        }
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
            .clipDragSource(item)
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
            .simultaneousGesture(TapGesture().onEnded { select(index) })
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

    /// Sync state on the left, keyboard hints on the right (the design footer):
    /// keycaps with room to breathe, not a cramped icon+label run.
    private var panelFooter: some View {
        HStack(spacing: GanchoTokens.Spacing.md) {
            SyncStatusView(status: model.syncStatus)
            captureIndicator
            PasteStackStrip()
            Spacer(minLength: 0)
            hint("navigate", keys: ["arrow.up", "arrow.down"])
            hint("actions", keys: ["arrow.right"])
            hint("paste", keys: ["return"])
            Button {
                showShortcuts.toggle()
            } label: {
                Image(systemName: "questionmark.circle")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 20, height: 20)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Keyboard shortcuts (⌘/)")
            .accessibilityLabel("Keyboard shortcuts")
            .accessibilityIdentifier("panel-shortcuts-button")
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .padding(.top, GanchoTokens.Spacing.xxs)
        .padding(.horizontal, GanchoTokens.Spacing.xxs)
    }

    // MARK: - Keyboard cheat-sheet

    /// A dimmed scrim + a card listing every panel shortcut. Toggled by ⌘/ or
    /// the footer "?"; esc and a scrim tap dismiss it.
    @ViewBuilder private var boardPickerOverlay: some View {
        if showBoardPicker, let item = search.selectedItem {
            PanelBoardPicker(item: item) { showBoardPicker = false }
                .transition(.opacity)
        }
    }

    @ViewBuilder private var shortcutsOverlay: some View {
        if showShortcuts {
            ZStack {
                Color.black.opacity(0.18)
                    .ignoresSafeArea()
                    .contentShape(Rectangle())
                    .onTapGesture { showShortcuts = false }
                shortcutsCard
            }
            .transition(.opacity)
        }
    }

    private var shortcutsCard: some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
            HStack {
                Text("Keyboard shortcuts").font(.headline)
                Spacer()
                Button {
                    showShortcuts = false
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }
            shortcutLine(["↑", "↓"], "Move selection")
            shortcutLine(["→"], "Open actions")
            shortcutLine(["←"], "Back to list")
            shortcutLine(["⏎"], "Paste")
            shortcutLine(["⌥", "⏎"], "Paste without formatting")
            shortcutLine(["⌘", "1–9"], "Paste that numbered clip")
            shortcutLine(["⌘", "P"], "Pin or unpin")
            shortcutLine(["⌘", "S"], "Save as snippet")
            shortcutLine(["⌘", "B"], "Add to board")
            shortcutLine(["⌘", "↑"], "Recall recent searches")
            shortcutLine(["⌘", "A"], "Select all in search")
            shortcutLine(["esc"], "Close")
            shortcutLine(["⌘", "/"], "Show this list")
        }
        .padding(GanchoTokens.Spacing.md)
        .frame(width: 320)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: GanchoTokens.Radius.lg, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: GanchoTokens.Radius.lg, style: .continuous)
                .strokeBorder(.separator, lineWidth: GanchoTokens.Stroke.hairline)
        )
        .shadow(radius: 20, y: 8)
        .accessibilityIdentifier("panel-shortcuts")
    }

    private func shortcutLine(_ caps: [String], _ label: LocalizedStringKey) -> some View {
        HStack(spacing: GanchoTokens.Spacing.xs) {
            HStack(spacing: 3) { ForEach(caps, id: \.self) { keycap($0) } }
                .frame(width: 86, alignment: .leading)
            Text(label).font(.callout)
            Spacer(minLength: 0)
        }
    }

    private func keycap(_ text: String) -> some View {
        Text(verbatim: text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .frame(minWidth: 18, minHeight: 18)
            .padding(.horizontal, 4)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    // MARK: - Capture notice

    /// Why capture isn't recording right now — surfaced IN the panel so a copy
    /// that doesn't show up reads as "paused", not "broken". Private mode is the
    /// reactive common case; denied/screen-share are read when the panel opens.
    private enum CaptureNotice {
        case storageEphemeral, privateMode, denied, screenShare, paused
    }

    private var captureNotice: CaptureNotice? {
        // Data loss outranks everything: the user must know nothing is persisting.
        if model.storageIsEphemeral { return .storageEphemeral }
        if model.monitorStatus == .deniedByPrivacySettings { return .denied }
        if model.preferences.isPrivateModePaused { return .privateMode }
        if model.monitorStatus == .pausedByScreenShare { return .screenShare }
        if model.monitorStatus == .stopped { return .paused }
        return nil
    }

    /// True only when Gancho is actively watching the clipboard. Note that
    /// `.storageEphemeral` still captures (copies just don't persist), so it
    /// doesn't flip this — the banner covers that case. Do not derive this from
    /// `captureNotice`: that value intentionally prioritizes the most important
    /// banner when multiple conditions are true.
    private var isCapturing: Bool {
        model.monitorStatus == .running && !model.preferences.isPrivateModePaused
    }

    /// A positive "yes, capturing" signal in the footer (or a muted "paused"
    /// when it isn't) so a user who copies something and doesn't see it can tell
    /// at a glance whether Gancho is even watching. The WHY lives in the banner.
    private var captureIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(isCapturing ? GanchoTokens.Palette.success : Color.secondary)
                .frame(width: 6, height: 6)
            Text(isCapturing ? "Capturing" : "Paused")
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isCapturing ? Text("Capturing") : Text("Capture paused"))
        .accessibilityIdentifier("capture-indicator")
    }

    @ViewBuilder private func captureBanner(_ notice: CaptureNotice) -> some View {
        let tint = captureTint(notice)
        HStack(spacing: GanchoTokens.Spacing.xs) {
            Image(systemName: captureSymbol(notice)).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 0) {
                Text(captureTitle(notice)).font(.caption.weight(.semibold))
                Text(captureDetail(notice)).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let actionLabel = captureAction(notice) {
                Button(actionLabel) { handleCaptureAction(notice) }
                    .buttonStyle(.borderless)
                    .font(.caption.weight(.medium))
            }
        }
        .padding(.horizontal, GanchoTokens.Spacing.sm)
        .padding(.vertical, GanchoTokens.Spacing.xs)
        .background(
            tint.opacity(0.12),
            in: RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
        )
        .padding(.horizontal, GanchoTokens.Spacing.xxs)
        .accessibilityIdentifier("capture-notice")
    }

    private func captureSymbol(_ notice: CaptureNotice) -> String {
        switch notice {
        case .storageEphemeral: "externaldrive.badge.exclamationmark"
        case .privateMode: "eye.slash"
        case .denied: "exclamationmark.triangle.fill"
        case .screenShare: "rectangle.on.rectangle"
        case .paused: "pause.circle"
        }
    }

    private func captureTint(_ notice: CaptureNotice) -> Color {
        switch notice {
        case .privateMode, .screenShare, .paused: GanchoTokens.Palette.warning
        case .denied, .storageEphemeral: GanchoTokens.Palette.danger
        }
    }

    private func captureTitle(_ notice: CaptureNotice) -> LocalizedStringKey {
        switch notice {
        case .storageEphemeral: "History isn't being saved"
        case .privateMode: "Private Mode is on"
        case .denied: "Clipboard access is off"
        case .screenShare: "Paused while screen sharing"
        case .paused: "Capture is paused"
        }
    }

    private func captureDetail(_ notice: CaptureNotice) -> LocalizedStringKey {
        switch notice {
        case .storageEphemeral:
            "Gancho couldn't open its secure storage — clips vanish when you quit."
        case .privateMode: "New copies aren't being saved."
        case .denied: "Gancho can't see what you copy."
        case .screenShare: "Capture resumes when you stop sharing."
        case .paused: "Resume capture to save new copies."
        }
    }

    private func captureAction(_ notice: CaptureNotice) -> LocalizedStringKey? {
        switch notice {
        case .privateMode, .paused: "Resume"
        case .denied: "Fix"
        case .storageEphemeral, .screenShare: nil
        }
    }

    private func handleCaptureAction(_ notice: CaptureNotice) {
        switch notice {
        case .privateMode: model.togglePrivateMode()
        case .paused: model.togglePause()
        case .denied: model.permissionWindow.show(model: model)
        case .storageEphemeral, .screenShare: break
        }
    }

    /// The first-run empty-state hint. Normally "⌘C to start", but when capture
    /// is actually blocked it names the cause instead of misleading the user into
    /// thinking a copy will land (the banner above offers the one-tap fix).
    private var firstRunCaptureHint: LocalizedStringKey {
        switch captureNotice {
        case .privateMode: "Private Mode is on — resume it above to start saving."
        case .denied: "Clipboard access is off — turn it on above to start."
        case .screenShare: "Capture is paused while sharing your screen."
        case .paused: "Capture is paused — resume it above to start saving."
        default: "⌘C in any app to start"
        }
    }

    /// A keyboard hint: one or more keycaps followed by what they do.
    private func hint(_ label: LocalizedStringKey, keys: [String]) -> some View {
        HStack(spacing: GanchoTokens.Spacing.xxs) {
            ForEach(keys, id: \.self) { key in
                Image(systemName: key)
                    .font(.system(size: 9, weight: .semibold))
                    .frame(width: 17, height: 16)
                    .background(
                        .quaternary,
                        in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            Text(label)
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
            item: item, isSelected: index == search.selectedIndex,
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
    private func select(_ index: Int) {
        search.select(index)
        railFocus = nil
        focus = .search
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
            return
        }
        guard item.kind != .image, item.kind != .fileReference else {
            previewText = item.preview
            return
        }
        if case .text(let text)? = try? await model.store.content(for: item.id) {
            previewText = text
        } else {
            previewText = item.preview
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

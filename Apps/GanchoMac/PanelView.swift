import AppKit
import ClipboardCore
import Combine
import GanchoAI
import GanchoDesign
import GanchoKit
import SwiftUI

/// The history's type-filter rail (the design's All / Links / Code / Colors /
/// Images / Secrets pills).
enum ClipKindFilter: String, CaseIterable, Identifiable {
    case all, links, code, colors, images, secrets
    var id: String { rawValue }

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

    /// The clip kind whose tint colours the pill's dot (nil for All).
    var tintKind: ClipContentKind? {
        switch self {
        case .all: nil
        case .links: .url
        case .code: .code
        case .colors: .color
        case .images: .image
        case .secrets: .secret
        }
    }

    func matches(_ kind: ClipContentKind) -> Bool {
        switch self {
        case .all: true
        case .links: kind == .url
        case .code: kind == .code || kind == .json || kind == .uuid
        case .colors: kind == .color
        case .images: kind == .image
        case .secrets: kind == .secret || kind == .jwt || kind == .creditCard
        }
    }
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

/// Which zone owns the keyboard: the search field (list navigation) or the
/// peek (its action list). → moves focus into the peek, ← returns to the list.
enum PanelFocus: Hashable { case search, peek }

/// When the keyboard is "up" in the rails above the list: which rail and which
/// chip. ↑ from the first list row enters `.filters`, ↑ again `.boards`; ←→ move
/// within a rail, Space/Enter toggles. `nil` means the keyboard is in the list.
private enum RailFocus: Hashable {
    case boards(Int)  // 0 = "All clips", 1…n = model.boards[i-1]
    case filters(Int)  // index into ClipKindFilter.allCases
}

/// The floating history panel: compact, keyboard-first (the explicit design
/// decision vs Paste's full-width drawer). Every interaction works without
/// a mouse: type-to-search, ↑↓ to navigate, → into the peek, Enter to paste.
struct PanelView: View {
    @Environment(AppModel.self) private var model
    @FocusState private var focus: PanelFocus?
    @State private var query = ""
    @State private var results: [ClipItem] = []
    @State private var selectedIndex = 0
    /// Non-nil when the keyboard moved up into the filter/board rails.
    @State private var railFocus: RailFocus?
    @State private var previewText = ""
    @State private var kindFilter: ClipKindFilter = .all
    /// nil = "All clips"; otherwise the selected board's id. Boards are a
    /// higher axis than the kind filter and sit above it in the rail.
    @State private var selectedBoardID: UUID?
    @State private var boardSheet: BoardSheet?
    @State private var boardNameField = ""
    /// The snippet whose keyword the query matches exactly — typing it surfaces
    /// a one-keystroke insert banner above the list (the in-app expansion path).
    @State private var snippetMatch: ClipItem?
    /// Set when invoking a template snippet ({fields}) — drives the fill sheet.
    @State private var fillRequest: SnippetFillRequest?
    /// "Ask your clipboard": the grounded answer + its source clips, and whether
    /// the on-device model is currently answering.
    @State private var answer: AppModel.ClipboardAnswer?
    @State private var isAsking = false

    /// The rows actually shown: `results` narrowed by the active filter pill.
    private var filtered: [ClipItem] {
        kindFilter == .all ? results : results.filter { kindFilter.matches($0.kind) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: GanchoTokens.Spacing.sm) {
            listColumn
                .frame(width: 440)
            // The peek opens BESIDE the list (not a modal) and follows the
            // hovered / selected clip — Quick-Look-style.
            if let selected = selectedItem {
                ClipPeek(item: selected, text: previewText, focus: $focus)
                    .frame(width: 400)
                    .ganchoSurface(radius: GanchoTokens.Radius.lg)
                    .transition(.opacity)
            }
        }
        .padding(GanchoTokens.Spacing.sm)
        .frame(minWidth: selectedItem == nil ? 472 : 864, minHeight: 520)
        .task { await refresh() }
        .task { await model.refreshBoards() }
        .onChange(of: query) { _, _ in
            // A new query invalidates a previous answer and drops rail focus
            // (you're typing in the search field again).
            answer = nil
            railFocus = nil
            Task { await refresh() }
        }
        .onChange(of: model.recentItems) { _, _ in
            Task { await refresh() }
        }
        .onChange(of: selectedBoardID) { _, _ in
            Task { await refresh() }
        }
        .alert(boardSheetTitle, isPresented: boardSheetPresented) {
            TextField("Board name", text: $boardNameField)
            Button("Cancel", role: .cancel) {}
            Button(boardSheetConfirm) { commitBoardSheet() }
        }
        .sheet(item: $fillRequest) { request in
            SnippetFillSheet(request: request) { values in
                model.pasteSnippet(request.snippet, values: values)
                fillRequest = nil
            } onCancel: {
                fillRequest = nil
            }
        }
        // Load the peek for the selected clip, keyed on its id and debounced:
        // arrowing fast cancels the in-flight load, so only the clip you land on
        // is read and rendered — keeps navigation responsive.
        .task(id: selectedItem?.id) {
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

    /// The history list: search, rows, and the sync footer. The peek lives in a
    /// sibling column (see `body`).
    private var listColumn: some View {
        VStack(spacing: GanchoTokens.Spacing.xs) {
            SearchField("Search your clipboard", text: $query)
                .focused($focus, equals: .search)
                .onKeyPress(.downArrow) { navigateDown() }
                .onKeyPress(.upArrow) { navigateUp() }
                .onKeyPress(.leftArrow) { navigateLeft() }
                .onKeyPress(.rightArrow) { navigateRight() }
                .onKeyPress(.space, phases: .down) { _ in
                    // In a rail, Space toggles the focused chip (and won't type a
                    // space); in the list it falls through to the search field.
                    guard railFocus != nil else { return .ignored }
                    _ = toggleFocusedRail()
                    return .handled
                }
                .onKeyPress(.return, phases: .down) { press in
                    // In a rail, Enter toggles the focused chip. Otherwise an exact
                    // keyword match takes Enter (you typed the snippet shortcut on
                    // purpose); else Enter pastes the selection.
                    if railFocus != nil {
                        _ = toggleFocusedRail()
                        return .handled
                    }
                    if let match = snippetMatch {
                        invokeSnippet(match)
                    } else {
                        pasteSelected(plain: press.modifiers.contains(.option))
                    }
                    return .handled
                }
                .onKeyPress(.escape) {
                    model.panel.hide()
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
                        filtered.indices.contains(digit - 1)
                    else { return .ignored }
                    model.paste(filtered[digit - 1])
                    return .handled
                }
                .onKeyPress(characters: CharacterSet(charactersIn: "p"), phases: .down) { press in
                    guard press.modifiers.contains(.command), let item = selectedItem else {
                        return .ignored
                    }
                    model.togglePin(item)
                    return .handled
                }
                .onKeyPress(characters: CharacterSet(charactersIn: "s"), phases: .down) { press in
                    guard press.modifiers.contains(.command), let item = selectedItem else {
                        return .ignored
                    }
                    model.promoteToSnippet(item)
                    return .handled
                }

            boardRail

            filterRail

            if let snippetMatch {
                snippetBanner(snippetMatch)
            }

            if model.askAvailable, !query.isEmpty {
                askRow
            }

            if filtered.isEmpty {
                emptyState
            } else {
                recentHeader
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: GanchoTokens.Spacing.xxs) {
                            ForEach(Array(filtered.enumerated()), id: \.element.id) { index, item in
                                row(for: item, index: index)
                                    .id(item.id)
                                    // Load this image's thumbnail once it scrolls
                                    // into view (LazyVStack → visible rows only).
                                    .task(id: item.id) {
                                        await model.thumbnails.ensureLoaded(item)
                                    }
                                    // Single click SELECTS, double-click PASTES; hover no
                                    // longer moves the selection (arrows + click only), so the
                                    // mouse can rest over the list without hijacking it.
                                    .onTapGesture(count: 2) { model.paste(item) }
                                    .onTapGesture { select(index) }
                                    .contextMenu { contextMenu(for: item) }
                            }
                        }
                        .padding(.horizontal, GanchoTokens.Spacing.xxs)
                    }
                    .onChange(of: selectedIndex) { _, index in
                        guard filtered.indices.contains(index) else { return }
                        proxy.scrollTo(filtered[index].id)
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
        let isActive = filter == kindFilter
        let isFocused = railFocus == .filters(ClipKindFilter.allCases.firstIndex(of: filter) ?? -1)
        return Button {
            kindFilter = filter
            selectedIndex = 0
        } label: {
            HStack(spacing: 4) {
                if let kind = filter.tintKind {
                    Circle()
                        .fill(GanchoTokens.Palette.kindTint(for: kind))
                        .frame(width: 6, height: 6)
                }
                Text(filter.title).font(.caption.weight(.medium))
            }
            .padding(.horizontal, GanchoTokens.Spacing.xs)
            .padding(.vertical, 3)
            .background(
                isActive ? AnyShapeStyle(GanchoTokens.Palette.accent) : AnyShapeStyle(.quaternary),
                in: Capsule()
            )
            .foregroundStyle(isActive ? AnyShapeStyle(Color.white) : AnyShapeStyle(.secondary))
            .overlay(railRing(isFocused))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("filter-\(filter.rawValue)")
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
                    isActive: selectedBoardID == nil, isFocused: railFocus == .boards(0),
                    identifier: "board-all"
                ) {
                    selectedBoardID = nil
                }
                ForEach(Array(model.boards.enumerated()), id: \.element.id) { index, board in
                    boardChip(
                        label: board.isSystem ? Text("Favorites") : Text(verbatim: board.name),
                        systemImage: board.sfSymbol,
                        isActive: selectedBoardID == board.id,
                        isFocused: railFocus == .boards(index + 1),
                        identifier: "board-\(board.id.uuidString)"
                    ) {
                        selectedBoardID = board.id
                    }
                    .contextMenu {
                        if !board.isSystem {
                            Button("Rename board…") {
                                boardNameField = board.name
                                boardSheet = .rename(board)
                            }
                            Button("Delete board", role: .destructive) {
                                if selectedBoardID == board.id { selectedBoardID = nil }
                                model.deleteBoard(board)
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
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: systemImage).font(.caption2)
                label.font(.caption.weight(.medium))
            }
            .padding(.horizontal, GanchoTokens.Spacing.xs)
            .padding(.vertical, 3)
            .background(
                isActive ? AnyShapeStyle(GanchoTokens.Palette.accent) : AnyShapeStyle(.quaternary),
                in: Capsule()
            )
            .foregroundStyle(isActive ? AnyShapeStyle(Color.white) : AnyShapeStyle(.secondary))
            .overlay(railRing(isFocused))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
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
        case .new: model.createBoard(named: name)
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
        let question = query
        answer = nil
        isAsking = true
        Task {
            let result = await model.askClipboard(question)
            isAsking = false
            answer = result
        }
    }

    private var recentHeader: some View {
        HStack {
            Text("Recent")
            Spacer()
            Text("\(filtered.count) clips")
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.tertiary)
        .textCase(.uppercase)
        .padding(.horizontal, GanchoTokens.Spacing.xs)
    }

    /// Sync state on the left, keyboard hints on the right (the design footer):
    /// keycaps with room to breathe, not a cramped icon+label run.
    private var panelFooter: some View {
        HStack(spacing: GanchoTokens.Spacing.md) {
            SyncStatusView(status: model.syncStatus)
            Spacer(minLength: 0)
            hint("navigate", keys: ["arrow.up", "arrow.down"])
            hint("actions", keys: ["arrow.right"])
            hint("paste", keys: ["return"])
        }
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .padding(.top, GanchoTokens.Spacing.xxs)
        .padding(.horizontal, GanchoTokens.Spacing.xxs)
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
            if query.isEmpty {
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
                Text("⌘C in any app to start")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
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
                Text("No clips for “\(query)”. Try another word or clear the filters.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Text("Press esc to clear the search")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, GanchoTokens.Spacing.xxs)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, GanchoTokens.Spacing.lg)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(query.isEmpty ? "panel-empty-firstrun" : "panel-empty-noresults")
    }

    private func row(for item: ClipItem, index: Int) -> some View {
        // ClipCard is the design's ClipRow: kind glyph (or colour swatch),
        // title/preview, pin / Universal-Clipboard markers, and the ⌘N
        // quick-paste badge for the first nine rows.
        ClipCard(
            item: item, isSelected: index == selectedIndex,
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
        Button("Promote to Library") {
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
                model.createBoard(named: String(localized: "Board"))
            }
            Button("Remove from board") { model.removeFromAllBoards(item) }
        }
        Button("Delete", role: .destructive) {
            model.delete(item)
        }
    }

    private var selectedItem: ClipItem? {
        filtered.indices.contains(selectedIndex) ? filtered[selectedIndex] : nil
    }

    private func move(_ delta: Int) -> KeyPress.Result {
        // Always consume arrows so focus never leaves the search field — with
        // no results there is simply nothing to move (Spotlight behavior).
        // Returning .ignored here let the arrow propagate and steal focus.
        guard !filtered.isEmpty else { return .handled }
        selectedIndex = (selectedIndex + delta + filtered.count) % filtered.count
        return .handled
    }

    private func pasteSelected(plain: Bool) {
        guard let item = selectedItem else { return }
        model.paste(item, asPlainText: plain)
    }

    /// Select a row without acting on it (the click + arrow path). Re-grabs
    /// search focus so type-to-search and Enter-to-paste keep working after a
    /// click lands focus on the row.
    private func select(_ index: Int) {
        selectedIndex = index
        railFocus = nil
        focus = .search
    }

    // MARK: - Rail keyboard navigation (filters + boards above the list)

    private var currentFilterIndex: Int {
        ClipKindFilter.allCases.firstIndex(of: kindFilter) ?? 0
    }
    /// 0 = "All clips"; otherwise the selected board's slot (1-based).
    private var currentBoardIndex: Int {
        guard let id = selectedBoardID else { return 0 }
        return (model.boards.firstIndex { $0.id == id }).map { $0 + 1 } ?? 0
    }

    /// ↑: out of the list at row 0 into the filters, then up to the boards.
    private func navigateUp() -> KeyPress.Result {
        switch railFocus {
        case nil:
            guard selectedIndex == 0 else { return move(-1) }
            railFocus = .filters(currentFilterIndex)
        case .filters:
            railFocus = .boards(currentBoardIndex)
        case .boards:
            break  // top of the stack
        }
        return .handled
    }

    /// ↓: boards → filters → back into the list.
    private func navigateDown() -> KeyPress.Result {
        switch railFocus {
        case nil:
            return move(1)
        case .filters:
            railFocus = nil
            selectedIndex = 0
        case .boards:
            railFocus = .filters(currentFilterIndex)
        }
        return .handled
    }

    /// ← moves within the focused rail; in the list it is the search cursor.
    private func navigateLeft() -> KeyPress.Result {
        switch railFocus {
        case .filters(let i): railFocus = .filters(max(0, i - 1))
        case .boards(let i): railFocus = .boards(max(0, i - 1))
        case nil: return .ignored
        }
        return .handled
    }

    /// → moves within the focused rail; in the list it hands off to the peek.
    private func navigateRight() -> KeyPress.Result {
        switch railFocus {
        case .filters(let i):
            railFocus = .filters(min(ClipKindFilter.allCases.count - 1, i + 1))
        case .boards(let i):
            railFocus = .boards(min(model.boards.count, i + 1))
        case nil:
            guard selectedItem != nil else { return .ignored }
            focus = .peek
        }
        return .handled
    }

    /// Space / Enter on a focused chip: select it, or deselect (back to All) if
    /// it is already active. Returns false when the keyboard is not in a rail.
    @discardableResult
    private func toggleFocusedRail() -> Bool {
        switch railFocus {
        case .filters(let i):
            let filter = ClipKindFilter.allCases[i]
            kindFilter = (kindFilter == filter) ? .all : filter
            selectedIndex = 0
            return true
        case .boards(let i):
            if i == 0 {
                selectedBoardID = nil
            } else if model.boards.indices.contains(i - 1) {
                let board = model.boards[i - 1]
                selectedBoardID = (selectedBoardID == board.id) ? nil : board.id
            }
            return true
        case nil:
            return false
        }
    }

    /// Load the selected clip's full text for the peek beside the list. Only
    /// text-like clips need a content read; reading an image/file blob from
    /// disk on every selection change would lag navigation, so those fall back
    /// to the cheap stored preview.
    private func loadSelectedText() async {
        guard let item = selectedItem else {
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

    /// Type-to-search: first keystroke already narrows; empty query shows
    /// recents (pins first, store order).
    private func refresh() async {
        let board = selectedBoardID
        if query.isEmpty {
            if let board, let grdb = model.grdbStore {
                results = (try? await grdb.items(inBoard: board)) ?? []
            } else {
                results = (try? await model.store.items(offset: 0, limit: 50)) ?? []
            }
        } else if let grdb = model.grdbStore {
            results =
                (try? await grdb.search(ClipSearchQuery(text: query, boardID: board), limit: 50))
                ?? []
        } else {
            let all = (try? await model.store.items(offset: 0, limit: 200)) ?? []
            results = all.filter { $0.preview.localizedCaseInsensitiveContains(query) }
        }
        // A query that exactly matches a snippet's keyword offers a one-keystroke
        // insert (filling {fields} first if it's a template).
        snippetMatch = query.isEmpty ? nil : await model.snippet(matchingKeyword: query)
        selectedIndex = 0
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
                fillRequest = SnippetFillRequest(snippet: snippet, body: body, fields: fields)
            }
        }
    }
}

/// ClipPeek — a Quick-Look-style rich preview (the design's component): a
/// type-aware body, an insight strip (source app · time · expiry), the kind's
/// offline transforms, and Paste / Paste plain / Pin. Sensitive clips stay
/// masked here; revealing them takes an explicit transform.
struct ClipPeek: View {
    let item: ClipItem
    let text: String
    /// Shared with the list: the peek owns the keyboard when this equals `.peek`
    /// (entered with → from the list, left with ←).
    var focus: FocusState<PanelFocus?>.Binding
    @Environment(AppModel.self) private var model
    @State private var actionResult: String?
    @State private var boardIDs: Set<UUID> = []
    /// Smart Paste can run the on-device model — show a spinner while it thinks.
    @State private var isThinking = false
    /// The board auto-board thinks this clip belongs to (a suggestion, never
    /// auto-filed); nil until computed or once accepted/dismissed.
    @State private var suggestedBoard: Pinboard?
    /// The highlighted action while the peek owns the keyboard (focus == .peek).
    @State private var actionIndex = 0

    /// Masked clips show their stored masked preview, not the raw content. The
    /// peek is a preview, so cap very long clips: laying out a huge Text here on
    /// every selection change is what froze navigation on big clips (e.g. a long
    /// markdown doc).
    private var bodyText: String {
        let raw = item.isSensitive ? item.preview : text
        let limit = 4000
        return raw.count > limit ? String(raw.prefix(limit)) + "\n…" : raw
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.sm) {
            header
            if let suggestedBoard {
                suggestionChip(suggestedBoard)
            }
            peekBody
            insightStrip
            if canSmartPaste {
                smartPasteMenu
            }
            if isThinking {
                Label("Thinking…", systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .symbolEffect(.pulse, options: .repeating)
            } else if let actionResult, !actionResult.isEmpty {
                resultBox(actionResult)
            }
            actionsList
        }
        .padding(GanchoTokens.Spacing.md)
        // Sized to its content and pinned to the top — the peek is a shorter
        // detail card, not the full height of the list.
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .accessibilityIdentifier("clip-peek")
        // The peek owns the keyboard while focus == .peek: ↑↓ move among the
        // actions, Enter runs the focused one, ← hands focus back to the list.
        .focusable()
        .focusEffectDisabled()
        .focused(focus, equals: .peek)
        .onKeyPress(.upArrow) { moveAction(-1) }
        .onKeyPress(.downArrow) { moveAction(1) }
        .onKeyPress(.leftArrow) {
            focus.wrappedValue = .search
            return .handled
        }
        .onKeyPress(.return) {
            runFocusedAction()
            return .handled
        }
        .onKeyPress(.escape) {
            model.panel.hide()
            return .handled
        }
        .onChange(of: focus.wrappedValue) { _, newValue in
            if newValue == .peek { actionIndex = 0 }
        }
        .task(id: item.id) { await model.thumbnails.ensureLoaded(item) }
        .task(id: item.id) { boardIDs = await model.boardMembership(for: item) }
        .task(id: item.id) { suggestedBoard = await model.suggestedBoard(for: item) }
    }

    /// "Add to Dev?" — the one-tap board suggestion. Accepting files the clip;
    /// the ✕ dismisses it. Auto-board never files silently.
    private func suggestionChip(_ board: Pinboard) -> some View {
        HStack(spacing: GanchoTokens.Spacing.xs) {
            Image(systemName: "sparkles").foregroundStyle(GanchoTokens.Palette.accent)
            Text("Add to \(board.name)?").font(.caption.weight(.medium)).lineLimit(1)
            Spacer(minLength: 0)
            Button("Add") {
                model.assign(item, toBoard: board)
                boardIDs.insert(board.id)
                suggestedBoard = nil
            }
            .buttonStyle(.borderless)
            Button {
                suggestedBoard = nil
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless).foregroundStyle(.tertiary)
            .accessibilityLabel(Text("Dismiss"))
        }
        .padding(.horizontal, GanchoTokens.Spacing.sm)
        .padding(.vertical, 6)
        .background(
            GanchoTokens.Palette.accent.opacity(0.1),
            in: RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
        )
        .accessibilityIdentifier("board-suggestion")
    }

    private var header: some View {
        HStack(spacing: GanchoTokens.Spacing.xs) {
            TypeBadge(kind: item.kind)
            if !item.title.isEmpty {
                Text(item.title).font(.headline).lineLimit(1)
            }
            Spacer(minLength: 0)
            boardMenu
            Button {
                model.togglePin(item)
            } label: {
                Image(systemName: item.isPinned ? "pin.fill" : "pin")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(Text(item.isPinned ? "Unpin" : "Pin"))
            .accessibilityIdentifier("preview-pin")
        }
    }

    /// Toggle this clip in/out of any board, with a checkmark on the boards it
    /// already belongs to (a clip can be in several). Favorites is just another
    /// board here — the protected one.
    private var boardMenu: some View {
        Menu {
            ForEach(model.boards) { board in
                Button {
                    Task {
                        await model.setBoardMembership(
                            item, board: board, member: !boardIDs.contains(board.id))
                        boardIDs = await model.boardMembership(for: item)
                    }
                } label: {
                    Label {
                        board.isSystem ? Text("Favorites") : Text(verbatim: board.name)
                    } icon: {
                        Image(
                            systemName: boardIDs.contains(board.id) ? "checkmark" : board.sfSymbol)
                    }
                }
            }
        } label: {
            Image(systemName: boardIDs.isEmpty ? "tray" : "tray.full")
        }
        .menuIndicator(.hidden)
        .buttonStyle(.borderless)
        .accessibilityLabel(Text("Add to board"))
        .accessibilityIdentifier("preview-board")
    }

    /// Type-aware body: colour clips show a big swatch beside the value;
    /// everything else shows its (syntax-tinted for code) text.
    @ViewBuilder private var peekBody: some View {
        if item.kind == .image, !item.isSensitive,
            let thumbnail = model.thumbnails.cached(for: item.id)
        {
            thumbnail
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: 220, alignment: .topLeading)
                .clipShape(
                    RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous))
        } else if item.kind == .color, !item.isSensitive, let color = Color(hexString: text) {
            HStack(spacing: GanchoTokens.Spacing.sm) {
                RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
                    .fill(color)
                    .frame(width: 56, height: 56)
                    .overlay(
                        RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous)
                            .strokeBorder(.separator, lineWidth: GanchoTokens.Stroke.hairline))
                Text(text).font(.body.monospaced()).textSelection(.enabled)
                Spacer(minLength: 0)
            }
        } else {
            ScrollView {
                Text(highlighted)
                    .font(item.kind == .code ? .body.monospaced() : .body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 200)
        }
    }

    /// Source app · relative time · expiry — the design's insight chips.
    private var insightStrip: some View {
        HStack(spacing: GanchoTokens.Spacing.md) {
            if let bundleID = item.sourceAppBundleID {
                Label {
                    Text(SourceApp.displayName(forBundleID: bundleID))
                } icon: {
                    if let icon = SourceApp.icon(forBundleID: bundleID) {
                        Image(nsImage: icon).resizable().frame(width: 13, height: 13)
                    } else {
                        Image(systemName: "app.dashed")
                    }
                }
                .accessibilityIdentifier("peek-source-app")
            }
            Label {
                Text(item.createdAt, style: .relative)
            } icon: {
                Image(systemName: "clock")
            }
            if let expiresAt = item.expiresAt {
                Label {
                    Text(expiresAt, style: .relative)
                } icon: {
                    Image(systemName: "hourglass")
                }
                .foregroundStyle(
                    expiresAt.timeIntervalSinceNow < 600
                        ? AnyShapeStyle(GanchoTokens.Palette.warning) : AnyShapeStyle(.secondary))
            }
            Spacer(minLength: 0)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .labelStyle(.titleAndIcon)
        .lineLimit(1)
    }

    /// One navigable action in the peek. The action list is the keyboard
    /// surface: ↑↓ move among these, Enter runs the focused one, click runs it.
    private struct PeekAction: Identifiable {
        let id: String
        let title: LocalizedStringKey
        let symbol: String
        let run: () -> Void
    }

    /// Paste variants first (the common case), then the per-kind Dev Actions.
    /// Smart Paste keeps its own menu (it is async and has a language submenu).
    private var navActions: [PeekAction] {
        var actions: [PeekAction] = [
            PeekAction(id: "preview-paste", title: "Paste", symbol: "doc.on.clipboard") {
                model.paste(item)
            },
            PeekAction(id: "preview-paste-plain", title: "Paste plain", symbol: "doc.plaintext") {
                model.paste(item, asPlainText: true)
            },
        ]
        for action in DevActions.actions(for: item.kind) {
            actions.append(
                PeekAction(
                    id: "dev-action-\(action.id.rawValue)",
                    title: LocalizedStringKey(action.title), symbol: "wand.and.sparkles"
                ) {
                    actionResult = (try? action.transform(text)) ?? ""
                    UserDefaults.standard.set(
                        UserDefaults.standard.integer(forKey: "dev-actions-run") + 1,
                        forKey: "dev-actions-run")
                })
        }
        return actions
    }

    /// The keyboard-navigable action list (Quick-Look-style). The focused row is
    /// highlighted only while the peek owns the keyboard (focus == .peek), so the
    /// list and the peek never look "both selected".
    private var actionsList: some View {
        VStack(spacing: 2) {
            ForEach(Array(navActions.enumerated()), id: \.element.id) { index, action in
                let isFocused = focus.wrappedValue == .peek && index == actionIndex
                HStack(spacing: GanchoTokens.Spacing.xs) {
                    Image(systemName: action.symbol).frame(width: 16)
                    Text(action.title).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .font(.body)
                .padding(.horizontal, GanchoTokens.Spacing.sm)
                .padding(.vertical, 6)
                .background(
                    isFocused
                        ? AnyShapeStyle(GanchoTokens.Palette.accent.opacity(0.18))
                        : AnyShapeStyle(.clear),
                    in: RoundedRectangle(cornerRadius: GanchoTokens.Radius.sm, style: .continuous)
                )
                .contentShape(Rectangle())
                .onTapGesture {
                    actionIndex = index
                    action.run()
                }
                .accessibilityIdentifier(action.id)
            }
        }
    }

    private func moveAction(_ delta: Int) -> KeyPress.Result {
        let count = navActions.count
        guard count > 0 else { return .handled }
        actionIndex = (actionIndex + delta + count) % count
        return .handled
    }

    private func runFocusedAction() {
        guard navActions.indices.contains(actionIndex) else { return }
        navActions[actionIndex].run()
    }

    /// Smart Paste fits text clips only and never a masked secret. Model-backed
    /// rewrites need Apple Intelligence, but deterministic PII redaction remains
    /// available whenever the user kept the Smart Paste toggle on.
    private var canSmartPaste: Bool {
        model.smartPasteAvailable && !item.isSensitive
            && item.kind != .image && item.kind != .fileReference && item.kind != .color
    }

    /// On-device rewrite menu (the design's "Smart paste"): summarize, fix
    /// grammar, change tone, pull key points — the result lands in the box below
    /// for review before pasting.
    private var smartPasteMenu: some View {
        Menu {
            ForEach(SmartPasteAction.allCases) { action in
                if action == .redactPII || model.smartPasteModelAvailable {
                    Button {
                        runSmartPaste(action)
                    } label: {
                        Label(LocalizedStringKey(action.titleKey), systemImage: action.symbolName)
                    }
                }
            }
            if model.smartPasteModelAvailable {
                Divider()
                Menu {
                    ForEach(Self.translateLanguageCodes, id: \.self) { code in
                        Button(Self.localizedLanguageName(code)) {
                            runTranslate(to: Self.englishLanguageName(code))
                        }
                    }
                } label: {
                    Label("Translate to", systemImage: "globe")
                }
            }
        } label: {
            Label("Smart paste", systemImage: "sparkles")
                .font(.body.weight(.medium))
                .padding(.horizontal, GanchoTokens.Spacing.sm)
                .padding(.vertical, GanchoTokens.Spacing.xxs)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .ganchoSurface(radius: GanchoTokens.Radius.md)
        .disabled(isThinking)
        .accessibilityIdentifier("smart-paste-menu")
    }

    private func runSmartPaste(_ action: SmartPasteAction) {
        actionResult = nil
        isThinking = true
        Task {
            let result = await model.smartPaste(text, action: action)
            isThinking = false
            actionResult = result ?? String(localized: "Couldn’t run that — try again.")
        }
    }

    /// Common targets for Smart Paste translation. Names render in the user's
    /// language (via `Locale`); the prompt gets the English name for clarity.
    private static let translateLanguageCodes = [
        "en", "es", "fr", "de", "it", "pt", "ja", "ko", "zh",
    ]
    private static func localizedLanguageName(_ code: String) -> String {
        Locale.current.localizedString(forLanguageCode: code) ?? code
    }
    private static func englishLanguageName(_ code: String) -> String {
        Locale(identifier: "en").localizedString(forLanguageCode: code) ?? code
    }

    private func runTranslate(to language: String) {
        actionResult = nil
        isThinking = true
        Task {
            let result = await model.smartTranslate(text, to: language)
            isThinking = false
            actionResult = result ?? String(localized: "Couldn’t run that — try again.")
        }
    }

    private func resultBox(_ result: String) -> some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xxs) {
            ScrollView {
                Text(result)
                    .font(.body.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 140)
            HStack(spacing: GanchoTokens.Spacing.xxs) {
                ActionButton("Paste", systemImage: "doc.on.clipboard", identifier: "paste-result") {
                    model.pasteText(result)
                }
                ActionButton("Copy result", systemImage: "doc.on.doc", identifier: "copy-result") {
                    SystemPasteboardWriter().write(.text(result), asPlainText: true)
                    model.toasts.show(GanchoToast(message: "Copied"))
                }
            }
        }
    }

    /// Fully local syntax tint for code clips, shared with the Library editor
    /// via `GanchoSyntax` (strings, comments, numbers, keywords, `{placeholder}`
    /// fields). Non-code clips render as plain text.
    private var highlighted: AttributedString {
        var attributed = AttributedString(bodyText)
        // The peek re-renders on every selection change; tokenizing a very
        // large clip there would lag navigation, so highlight only when the
        // clip is a reasonable size.
        guard item.kind == .code, bodyText.count <= 20_000 else { return attributed }
        for token in GanchoSyntax.tokens(in: bodyText) {
            let lower = bodyText.distance(from: bodyText.startIndex, to: token.range.lowerBound)
            let upper = bodyText.distance(from: bodyText.startIndex, to: token.range.upperBound)
            let lo = attributed.index(attributed.startIndex, offsetByCharacters: lower)
            let hi = attributed.index(attributed.startIndex, offsetByCharacters: upper)
            attributed[lo..<hi].foregroundColor = GanchoTokens.Syntax.color(for: token.kind)
        }
        return attributed
    }
}

/// A pending template insertion: the snippet, its resolved body, and the
/// {fields} to fill before paste.
struct SnippetFillRequest: Identifiable {
    let snippet: ClipItem
    let body: String
    let fields: [SnippetTemplate.Field]
    var id: UUID { snippet.id }
}

/// Collects values for a template snippet's {fields} before paste. Defaults
/// (`{name:World}`) pre-fill the editors; a live preview shows the filled
/// result. Keyboard-first: the first field focuses on appear, ⏎ inserts and
/// Esc cancels.
struct SnippetFillSheet: View {
    let request: SnippetFillRequest
    let onInsert: ([String: String]) -> Void
    let onCancel: () -> Void
    @State private var values: [String: String] = [:]
    @FocusState private var focusedField: String?

    private var filled: String {
        SnippetTemplate.fill(request.body, values: values)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.md) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Insert snippet").font(.caption).foregroundStyle(.secondary)
                Text(
                    verbatim: request.snippet.title.isEmpty
                        ? request.snippet.preview : request.snippet.title
                )
                .font(.headline).lineLimit(1)
            }

            ForEach(request.fields) { field in
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: field.name)
                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                    TextField(field.defaultValue ?? field.name, text: binding(for: field))
                        .textFieldStyle(.roundedBorder)
                        .focused($focusedField, equals: field.name)
                        .accessibilityIdentifier("fill-field-\(field.name)")
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Preview").font(.caption2).foregroundStyle(.secondary)
                ScrollView {
                    Text(filled)
                        .font(.body.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 120)
                .padding(GanchoTokens.Spacing.xs)
                .background(
                    .quaternary,
                    in: RoundedRectangle(cornerRadius: GanchoTokens.Radius.sm, style: .continuous))
            }

            HStack {
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Button("Insert") { onInsert(values) }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .accessibilityIdentifier("fill-insert")
            }
        }
        .padding(GanchoTokens.Spacing.lg)
        .frame(width: 380)
        .accessibilityIdentifier("snippet-fill-sheet")
        .onAppear {
            for field in request.fields where field.defaultValue != nil {
                values[field.name] = field.defaultValue
            }
            focusedField = request.fields.first?.name
        }
    }

    private func binding(for field: SnippetTemplate.Field) -> Binding<String> {
        Binding(
            get: { values[field.name] ?? "" },
            set: { values[field.name] = $0 })
    }
}

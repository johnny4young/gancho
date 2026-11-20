import AppKit
import ClipboardCore
import GanchoAI
import GanchoAppCore
import GanchoDesign
import GanchoKit
import SwiftUI

/// Sidebar sections and curation entry points; selection stays owned by the window.
extension LibraryView {
    var sidebar: some View {
        VStack(spacing: 0) {
            sidebarRows
            proFooter
        }
        // The title bar's safe area clears the traffic lights; the fill runs under them.
        .padding(.top, GanchoTokens.Spacing.sm)
        .background(GanchoTokens.Palette.controlFill.ignoresSafeArea())
    }

    /// A plain stack, not a `List`: the system would paint its own selection
    /// highlight in the accent under the row's wash.
    private var sidebarRows: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    scopeRows
                    boardRows
                    savedFilterRows
                    snippetRows
                    suggestedSection
                }
                .padding(.horizontal, GanchoTokens.Spacing.xs)
                .padding(.bottom, GanchoTokens.Spacing.sm)
            }
            .focusable()
            .focusEffectDisabled()
            .focused($sidebarFocused)
            .onKeyPress(.upArrow) { moveSelection(by: -1, proxy) }
            .onKeyPress(.downArrow) { moveSelection(by: 1, proxy) }
        }
    }

    /// ↑ and ↓ walk the rows in the order they are listed.
    private func moveSelection(by step: Int, _ proxy: ScrollViewProxy) -> KeyPress.Result {
        let rows: [LibrarySelection] =
            [.allClips, .pinned] + boards.map { .board($0.id) }
            + model.savedFilters.rules.map { .savedFilter($0.id) }
            + snippets.map { .snippet($0.id) }
        guard let index = rows.firstIndex(of: selection ?? .allClips),
            rows.indices.contains(index + step)
        else { return .ignored }
        requestSelection(rows[index + step])
        proxy.scrollTo(rows[index + step])
        return .handled
    }

    @ViewBuilder private var scopeRows: some View {
        navRow(.allClips, Text("All clips"), systemImage: "tray.full", count: allCount)
            .accessibilityIdentifier("library-all-clips")
        navRow(.pinned, Text("Pinned"), systemImage: "pin", count: pinnedCount)
            .accessibilityIdentifier("library-pinned")
    }

    @ViewBuilder private var boardRows: some View {
        sectionHeader(Text("Boards"), identifier: "board-new", addLabel: "New board") {
            boardNameField = ""
            boardSheet = .new
        }
        ForEach(boards) { board in
            navRow(
                .board(board.id),
                boardTitle(board),
                systemImage: board.sfSymbol, count: boardCounts[board.id] ?? 0,
                board: board
            )
            .boardDropTarget(
                board, ring: RoundedRectangle(cornerRadius: 6, style: .continuous)
            )
            .accessibilityIdentifier("library-board-\(board.id.uuidString)")
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
    }

    @ViewBuilder private var savedFilterRows: some View {
        sectionHeader(
            Text("Saved filters"), identifier: "saved-filter-new",
            addLabel: "New filter"
        ) {
            filterDraft = SmartCollectionRule(name: "")
        }
        ForEach(model.savedFilters.rules) { rule in
            selectable(savedFilterRow(rule), .savedFilter(rule.id))
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
                .padding(.horizontal, GanchoTokens.Spacing.xs)
            Button("Retry") { model.reloadSavedFilters() }
                .ganchoTextButton()
                .font(.caption)
                .padding(.horizontal, GanchoTokens.Spacing.xs)
                .accessibilityIdentifier("saved-filters-retry")
        } else if model.savedFilters.legacyImportFailed {
            Text("Older saved filters couldn’t be imported; the ones here are intact.")
                .font(.caption)
                .padding(.horizontal, GanchoTokens.Spacing.xs)
                .accessibilityIdentifier("saved-filters-import-warning")
        }
    }

    @ViewBuilder private var snippetRows: some View {
        sectionHeader(
            Text("Library · Snippets"), identifier: "snippet-new", addLabel: "New snippet"
        ) {
            createSnippet()
        }
        if snippets.isEmpty {
            Text("No snippets yet")
                .panelFont(.caption)
                .foregroundStyle(GanchoTokens.Palette.ink3)
                .padding(.horizontal, GanchoTokens.Spacing.xs)
        }
        ForEach(snippets) { snippet in
            selectable(snippetRow(snippet), .snippet(snippet.id))
        }
    }

    /// Cards quote the clip, so the group hides with the previews.
    @ViewBuilder private var suggestedSection: some View {
        let items = snippetSuggestions.items.filter { !model.pendingDeletionIDs.contains($0.id) }
        let hidden = snippetSuggestions.items.count - items.count
        if !items.isEmpty, !model.previewsHidden {
            Text("Suggested · \(snippetSuggestions.total - hidden)")
                .sidebarCaps()
                .padding(.horizontal, GanchoTokens.Spacing.xs)
                .frame(minHeight: 28)
                .padding(.top, GanchoTokens.Spacing.sm)
                .accessibilityIdentifier("snippet-suggestions-header")
            ForEach(items) { item in
                SnippetSuggestionCard(
                    item: item,
                    keep: { model.promoteToSnippet(item) },
                    never: { answerSuggestion(item, .never) },
                    dismiss: { answerSuggestion(item, .dismissed) }
                )
                .padding(.bottom, GanchoTokens.Spacing.xxs)
            }
        }
    }

    private func answerSuggestion(_ item: ClipItem, _ decision: SnippetSuggestionDecision) {
        Task { @MainActor in
            guard await model.decideSnippetSuggestion(item, decision) else { return }
            snippetSuggestions = await model.snippetSuggestions()
        }
    }

    private func navRow(
        _ selectionValue: LibrarySelection, _ label: Text, systemImage: String, count: Int,
        board: Pinboard? = nil
    ) -> some View {
        let row = HStack(spacing: GanchoTokens.Spacing.xs) {
            if let board {
                BoardIdentityMark(board: board, size: 14).frame(width: 18)
            } else {
                Image(systemName: systemImage)
                    .frame(width: 18)
                    .foregroundStyle(GanchoTokens.Palette.ink2)
            }
            label.lineLimit(1).foregroundStyle(GanchoTokens.Palette.ink)
            if let board, model.agentExposedBoardIDs.contains(board.id) {
                AgentExposedBadge(compact: true)
            }
            Spacer(minLength: 0)
            if count > 0 {
                rowCount(count)
                    .contentTransition(.numericText(value: Double(count)))
                    .animation(
                        GanchoMotion.quick(reduceMotion: reduceMotion),
                        value: count)
            }
        }
        return selectable(row, selectionValue)
    }

    /// A row that selects its scope on click and shows the neutral wash when
    /// it is the selection.
    private func selectable(_ row: some View, _ value: LibrarySelection) -> some View {
        let shape = RoundedRectangle(cornerRadius: GanchoTokens.Radius.sm, style: .continuous)
        let selected = (selection ?? .allClips) == value
        return
            row
            .padding(.horizontal, GanchoTokens.Spacing.xs)
            .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
            .ganchoTab(selected: selected, idle: .primary, in: shape)
            .contentShape(shape)
            .onTapGesture {
                sidebarFocused = true
                requestSelection(value)
            }
            .id(value)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func rowCount(_ count: Int) -> some View {
        Text(verbatim: "\(count)")
            .panelFont(.caption2, design: .monospaced)
            .foregroundStyle(GanchoTokens.Palette.ink3)
    }

    private func boardTitle(_ board: Pinboard) -> Text {
        board.displayTitle
    }

    private func snippetRow(_ snippet: ClipItem) -> some View {
        HStack(spacing: GanchoTokens.Spacing.xs) {
            Image(systemName: "text.alignleft")
                .frame(width: 18)
                .foregroundStyle(GanchoTokens.Palette.ink2)
            if snippet.title.isEmpty {
                Text("Untitled").lineLimit(1).foregroundStyle(GanchoTokens.Palette.ink3)
            } else {
                Text(verbatim: snippet.title).lineLimit(1)
                    .foregroundStyle(GanchoTokens.Palette.ink)
            }
            Spacer(minLength: 0)
            if let keyword = snippet.keyword, !keyword.isEmpty {
                Text(verbatim: keyword)
                    .panelFont(.caption2, .medium, design: .monospaced)
                    .foregroundStyle(GanchoTokens.Palette.ink2)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .frame(height: 16)
                    .background(
                        GanchoTokens.Palette.controlFill, in: RoundedRectangle(cornerRadius: 5)
                    )
                    .accessibilityIdentifier("snippet-keyword")
            }
        }
    }

    /// A saved filter with its glyph and how many clips it holds right now.
    private func savedFilterRow(_ rule: SmartCollectionRule) -> some View {
        HStack(spacing: GanchoTokens.Spacing.xs) {
            Image(systemName: "line.3.horizontal.decrease")
                .frame(width: 18)
                .foregroundStyle(GanchoTokens.Palette.ink2)
            Text(verbatim: rule.name).lineLimit(1).foregroundStyle(GanchoTokens.Palette.ink)
            Spacer(minLength: 0)
            if let count = filterCounts[rule.id] { rowCount(count) }
        }
    }

    private func sectionHeader(
        _ label: Text, identifier: String, addLabel: LocalizedStringKey,
        add: @escaping () -> Void
    )
        -> some View
    {
        HStack {
            label.sidebarCaps()
            Spacer()
            IconActionButton(addLabel, systemImage: "plus", identifier: identifier, action: add)
                .foregroundStyle(GanchoTokens.Palette.ink2)
        }
        .padding(.leading, GanchoTokens.Spacing.xs)
        .frame(minHeight: 28)
        .padding(.top, GanchoTokens.Spacing.sm)
    }

    private var userBoardCount: Int { boards.filter { !$0.isSystem }.count }

    private var proMeter: LibraryProMeter {
        // Pins in the in-memory fallback can't be managed or kept, so they don't meter.
        LibraryProMeter(
            boards: userBoardCount, pins: model.fullStore == nil ? 0 : pinnedCount,
            snippets: snippets.count)
    }

    /// The Free ceilings' only home: a bar filled to the fullest one and every
    /// ceiling's count, with a tail that warns as it fills. Opens the paywall.
    @ViewBuilder private var proFooter: some View {
        if model.tier != .pro {
            let meter = proMeter
            let caption = meterCaption(meter)
            let filled = meter.filledSegments()
            let fill = meterColor(meter.pressure)
            Button {
                model.paywallWindow.show(trigger: .freeLimitReached, model: model)
            } label: {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 3) {
                        ForEach(0..<5, id: \.self) { segment in
                            Capsule().fill(
                                segment < filled ? fill : GanchoTokens.Palette.hairline2)
                        }
                    }
                    .frame(height: 4)
                    Text(caption)
                        .panelFont(.caption2).foregroundStyle(GanchoTokens.Palette.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, GanchoTokens.Spacing.xs)
                .padding(.top, GanchoTokens.Spacing.sm)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .overlay(alignment: .top) { PanelHairline() }
            .padding(.horizontal, GanchoTokens.Spacing.xs)
            .padding(.bottom, GanchoTokens.Spacing.sm)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(verbatim: "gancho Pro"))
            .accessibilityValue(Text(verbatim: "\(Int((meter.fraction * 100).rounded()))%"))
            .accessibilityHint(Text(caption))
            .accessibilityIdentifier("library-pro")
        }
    }

    private func meterColor(_ pressure: FreeTierLimits.Pressure) -> Color {
        switch pressure {
        case .comfortable: GanchoTokens.Palette.ink
        case .almostFull: GanchoTokens.Palette.warning
        case .reached: GanchoTokens.Palette.danger
        }
    }

    private func meterCaption(_ meter: LibraryProMeter) -> String {
        let counts = meter.ceilings.map { ceiling in
            switch ceiling.kind {
            case .boards: String(localized: "\(ceiling.used) of \(ceiling.limit) boards")
            case .pins: String(localized: "\(ceiling.used) of \(ceiling.limit) pins")
            case .snippets: String(localized: "\(ceiling.used) of \(ceiling.limit) snippets")
            }
        }
        let tail: String
        switch meter.pressure {
        case .comfortable: tail = String(localized: "Pro removes every limit")
        case .almostFull: tail = String(localized: "Almost full")
        case .reached: tail = String(localized: "Limit reached")
        }
        return (counts + [tail]).joined(separator: " · ")
    }

}

extension View {
    /// A sidebar section's header: small mono capitals.
    fileprivate func sidebarCaps() -> some View {
        panelFont(.caption2, design: .monospaced)
            .textCase(.uppercase)
            .tracking(1)
            .foregroundStyle(GanchoTokens.Palette.ink3)
    }
}

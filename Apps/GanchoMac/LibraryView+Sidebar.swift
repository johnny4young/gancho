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
            List(selection: Binding(get: { selection }, set: { next in requestSelection(next) })) {
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
                } header: {
                    sectionHeader(
                        Text("Boards"), identifier: "board-new", addLabel: "New board",
                        badge: boardLimitBadge
                    ) {
                        boardNameField = ""
                        boardSheet = .new
                    }
                }

                Section {
                    ForEach(model.savedFilters.rules) { rule in
                        savedFilterRow(rule).tag(LibrarySelection.savedFilter(rule.id))
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
                            .ganchoTextButton()
                            .font(.caption)
                            .accessibilityIdentifier("saved-filters-retry")
                    } else if model.savedFilters.legacyImportFailed {
                        Text("Older saved filters couldn’t be imported; the ones here are intact.")
                            .font(.caption)
                            .accessibilityIdentifier("saved-filters-import-warning")
                    }
                } header: {
                    sectionHeader(
                        Text("Saved filters"), identifier: "saved-filter-new",
                        addLabel: "New filter"
                    ) {
                        filterDraft = SmartCollectionRule(name: "")
                    }
                }

                Section {
                    if snippets.isEmpty {
                        Text("No snippets yet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ForEach(snippets) { snippet in
                        snippetRow(snippet).tag(LibrarySelection.snippet(snippet.id))
                    }
                } header: {
                    sectionHeader(
                        Text("Library · Snippets"), identifier: "snippet-new",
                        addLabel: "New snippet", badge: snippetLimitBadge
                    ) {
                        createSnippet()
                    }
                }
            }
            .focused($sidebarFocused)
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
                    .contentTransition(.numericText(value: Double(count)))
                    .animation(
                        GanchoMotion.quick(reduceMotion: reduceMotion),
                        value: count)
            }
        }
        .tag(selectionValue)
    }

    private func boardTitle(_ board: Pinboard) -> Text {
        board.displayTitle
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
                Text(verbatim: keyword)
                    .font(.caption2.weight(.semibold).monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .padding(.horizontal, 4)
                    .frame(height: 16)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 5))
                    .accessibilityIdentifier("snippet-keyword")
            }
        }
    }

    /// A saved filter with its glyph and how many clips it holds right now.
    private func savedFilterRow(_ rule: SmartCollectionRule) -> some View {
        HStack(spacing: GanchoTokens.Spacing.xs) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .frame(width: 18)
                .foregroundStyle(.secondary)
            Text(verbatim: rule.name).lineLimit(1)
            Spacer(minLength: 0)
            if let count = filterCounts[rule.id] {
                Text(verbatim: "\(count)")
                    .font(.caption).monospacedDigit().foregroundStyle(.secondary)
            }
        }
    }

    private func sectionHeader(
        _ label: Text, identifier: String, addLabel: LocalizedStringKey, badge: Text? = nil,
        add: @escaping () -> Void
    )
        -> some View
    {
        HStack {
            label
            if let badge {
                badge.font(.caption2.monospacedDigit()).foregroundStyle(.tertiary)
            }
            Spacer()
            IconActionButton(addLabel, systemImage: "plus", identifier: identifier, action: add)
                .foregroundStyle(.secondary)
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

    private var proMeter: LibraryProMeter {
        LibraryProMeter(boards: userBoardCount, pins: pinnedCount, snippets: snippets.count)
    }

    /// The Pro card on Free: every ceiling's count, a bar filled to the fullest
    /// one, and a tail that warns as it fills. Opens the paywall.
    @ViewBuilder private var proFooter: some View {
        if model.tier != .pro {
            let meter = proMeter
            Button {
                model.paywallWindow.show(trigger: .freeLimitReached, model: model)
            } label: {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: GanchoTokens.Spacing.xs) {
                        Image(systemName: "star.fill")
                            .foregroundStyle(GanchoTokens.Palette.accentInk)
                        Text(verbatim: "gancho Pro").font(.caption.weight(.bold))
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.quaternary)
                            Capsule().fill(meterColor(meter.pressure))
                                .frame(width: proxy.size.width * meter.fraction)
                        }
                    }
                    .frame(height: 5)
                    .accessibilityHidden(true)
                    Text(meterCaption(meter))
                        .font(.caption2).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, GanchoTokens.Spacing.sm)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    GanchoTokens.Palette.accent.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: GanchoTokens.Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(GanchoTokens.Spacing.xs)
            .accessibilityElement(children: .combine)
            .accessibilityValue(Text(verbatim: "\(Int((meter.fraction * 100).rounded()))%"))
            .accessibilityIdentifier("library-pro")
        }
    }

    private func meterColor(_ pressure: FreeTierLimits.Pressure) -> Color {
        switch pressure {
        case .comfortable: GanchoTokens.Palette.accent
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

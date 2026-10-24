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
                            .ganchoTextButton()
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
                Image(systemName: "return")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .help(Text(verbatim: keyword))
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
                        .foregroundStyle(GanchoTokens.Palette.accentInk)
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

}

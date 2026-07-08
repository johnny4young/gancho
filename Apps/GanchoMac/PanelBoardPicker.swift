import GanchoAppCore
import GanchoDesign
import GanchoKit
import SwiftUI

/// The ⌘B board picker: file the selected clip into (or out of) boards without
/// the mouse. Type to filter; ↑↓ move; Return toggles the highlighted board;
/// ⌘Return (or the "New board" row) creates a board and files the clip; Esc
/// closes. Membership changes go through `AppModel.setBoardMembership`, which
/// marks the clip needs-upload, so the board set syncs.
struct PanelBoardPicker: View {
    @Environment(AppModel.self) private var model
    let item: ClipItem
    let onClose: () -> Void

    @State private var filter = ""
    @State private var memberIDs: Set<UUID> = []
    @State private var selection = 0
    @FocusState private var fieldFocused: Bool

    private var matches: [Pinboard] { BoardPickerFilter.matches(model.boards, query: filter) }
    private var canCreate: Bool { BoardPickerFilter.canCreate(model.boards, query: filter) }
    private var trimmedFilter: String {
        filter.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    /// Total selectable rows: the filtered boards plus the optional create row.
    private var rowCount: Int { matches.count + (canCreate ? 1 : 0) }

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { onClose() }
            card
        }
        .transition(.opacity)
        .task { memberIDs = await model.boardMembership(for: item) }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: GanchoTokens.Spacing.xs) {
            Text("Add to board").font(.headline)
            TextField("Filter or new board name", text: $filter)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .onKeyPress(.downArrow) { move(1) }
                .onKeyPress(.upArrow) { move(-1) }
                .onKeyPress(.escape) {
                    onClose()
                    return .handled
                }
                .onKeyPress(.return, phases: .down) { press in
                    if press.modifiers.contains(.command) {
                        createIfPossible()
                    } else {
                        commitSelection()
                    }
                    return .handled
                }
                .onChange(of: filter) { _, _ in selection = 0 }

            ScrollView {
                VStack(spacing: 2) {
                    ForEach(Array(matches.enumerated()), id: \.element.id) { index, board in
                        boardRow(board, index: index)
                    }
                    if canCreate {
                        createRow(index: matches.count)
                    }
                    if rowCount == 0 {
                        Text("No boards yet — type a name to create one.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                    }
                }
            }
            .frame(maxHeight: 240)

            Text("↑↓ move · ↩ toggle · ⌘↩ new board · esc close")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(GanchoTokens.Spacing.md)
        .frame(width: 320)
        .ganchoSurface(radius: GanchoTokens.Radius.lg)
        .onAppear { fieldFocused = true }
        .accessibilityIdentifier("board-picker")
    }

    private func boardRow(_ board: Pinboard, index: Int) -> some View {
        let isMember = memberIDs.contains(board.id)
        return HStack(spacing: GanchoTokens.Spacing.xs) {
            Image(systemName: isMember ? "checkmark.circle.fill" : board.sfSymbol)
                .foregroundStyle(isMember ? GanchoTokens.Palette.accent : Color.secondary)
            board.isSystem ? Text("Favorites") : Text(verbatim: board.name)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, GanchoTokens.Spacing.xs)
        .padding(.vertical, 5)
        .background(
            index == selection
                ? AnyShapeStyle(GanchoTokens.Palette.accent.opacity(0.14))
                : AnyShapeStyle(.clear),
            in: RoundedRectangle(cornerRadius: GanchoTokens.Radius.sm, style: .continuous)
        )
        .contentShape(Rectangle())
        .onTapGesture { toggle(board) }
    }

    private func createRow(index: Int) -> some View {
        HStack(spacing: GanchoTokens.Spacing.xs) {
            Image(systemName: "plus.circle.fill").foregroundStyle(GanchoTokens.Palette.accent)
            Text("New board")
            Text(verbatim: "“\(trimmedFilter)”").foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, GanchoTokens.Spacing.xs)
        .padding(.vertical, 5)
        .background(
            index == selection
                ? AnyShapeStyle(GanchoTokens.Palette.accent.opacity(0.14))
                : AnyShapeStyle(.clear),
            in: RoundedRectangle(cornerRadius: GanchoTokens.Radius.sm, style: .continuous)
        )
        .contentShape(Rectangle())
        .onTapGesture { createIfPossible() }
    }

    // MARK: - Actions

    private func move(_ delta: Int) -> KeyPress.Result {
        guard rowCount > 0 else { return .handled }
        selection = max(0, min(rowCount - 1, selection + delta))
        return .handled
    }

    /// Return: toggle the highlighted board, or create if the highlight is the
    /// create row.
    private func commitSelection() {
        if selection < matches.count {
            toggle(matches[selection])
        } else if canCreate {
            createIfPossible()
        }
    }

    private func toggle(_ board: Pinboard) {
        let member = memberIDs.contains(board.id)
        Task {
            await model.setBoardMembership(item, board: board, member: !member)
            memberIDs = await model.boardMembership(for: item)
        }
    }

    private func createIfPossible() {
        guard canCreate else { return }
        model.createBoard(named: trimmedFilter, assigning: item)
        onClose()
    }
}

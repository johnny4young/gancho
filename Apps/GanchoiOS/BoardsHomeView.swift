import ClipboardCore
import GanchoAI
import GanchoDesign
import GanchoKit
import GanchoSync
import GanchoTelemetry
import SwiftUI
import UIKit
import UniformTypeIdentifiers
import WidgetKit

/// A board's identity color as a small filled dot — the quiet per-board accent
/// the design asks for (green stays the app accent; Favorites wears the warm
/// favorite hue). Shared by every board row.
struct BoardDot: View {
    let board: Pinboard
    var size: CGFloat = 12

    var body: some View {
        Circle()
            .fill(board.isSystem ? GanchoTokens.Palette.warning : BoardColors.color(for: board))
            .frame(width: size, height: size)
    }
}

/// The move-to-board primitive: a quick "file this clip" sheet reached by
/// swiping a row. A clip can live in several boards at once, so this is a
/// multi-select — each tap toggles membership and saves immediately (the
/// change rides the clip's sync record). A board can be created inline, which
/// files the clip into it in one step.
struct MoveToBoardSheet: View {
    @Environment(IOSAppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let item: ClipItem
    @State private var memberIDs: Set<UUID> = []
    @State private var newBoardName = ""
    @FocusState private var newFieldFocused: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.boards) { board in
                        Button {
                            toggle(board)
                        } label: {
                            HStack(spacing: GanchoTokens.Spacing.sm) {
                                BoardDot(board: board)
                                board.isSystem
                                    ? Text("Favorites") : Text(verbatim: board.name)
                                Spacer()
                                if memberIDs.contains(board.id) {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(GanchoTokens.Palette.accent)
                                        .fontWeight(.semibold)
                                }
                            }
                        }
                        .tint(.primary)
                        .accessibilityIdentifier("move-board-\(board.id.uuidString)")
                    }
                }
                Section {
                    HStack {
                        Image(systemName: "plus").foregroundStyle(.secondary)
                        TextField("New board", text: $newBoardName)
                            .focused($newFieldFocused)
                            .submitLabel(.done)
                            .onSubmit(createAndFile)
                        if !newBoardName.trimmingCharacters(in: .whitespaces).isEmpty {
                            Button("Add", action: createAndFile).buttonStyle(.borderless)
                        }
                    }
                }
            }
            .navigationTitle("Add to board")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            await model.refreshBoards()
            memberIDs = await model.boardMembership(for: item)
        }
    }

    private func toggle(_ board: Pinboard) {
        let isMember = memberIDs.contains(board.id)
        Task {
            await model.setBoardMembership(item, board: board, member: !isMember)
            memberIDs = await model.boardMembership(for: item)
            UISelectionFeedbackGenerator().selectionChanged()
        }
    }

    private func createAndFile() {
        let name = newBoardName
        newBoardName = ""
        newFieldFocused = false
        Task {
            if await model.createBoard(named: name, filing: item) != nil {
                memberIDs = await model.boardMembership(for: item)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        }
    }
}

/// The boards home — the managed list the rail's quick switcher can't be.
/// Smart boards (All clips, Favorites) sit above the user's boards, each with
/// its identity color and live clip count. Tapping a board scopes the history
/// to it; a board can be created, renamed, or deleted here. Reorder, recolor,
/// and per-board sharing are deferred (each needs store or sync plumbing).
struct BoardsHomeView: View {
    @Environment(IOSAppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var totalCount = 0
    @State private var counts: [UUID: Int] = [:]
    @State private var showNewBoard = false
    @State private var newBoardName = ""
    @State private var renameTarget: Pinboard?
    @State private var renameField = ""

    private var systemBoards: [Pinboard] { model.boards.filter(\.isSystem) }
    private var userBoards: [Pinboard] { model.boards.filter { !$0.isSystem } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        open(nil)
                    } label: {
                        boardLabel(
                            Text("All clips"), icon: Image(systemName: "tray.full"),
                            tint: .secondary, count: totalCount)
                    }
                    .tint(.primary)
                    ForEach(systemBoards) { boardRow($0) }
                }
                Section("Boards") {
                    ForEach(userBoards) { boardRow($0) }
                    Button {
                        newBoardName = ""
                        showNewBoard = true
                    } label: {
                        Label("New board", systemImage: "plus")
                    }
                    .accessibilityIdentifier("boards-home-new")
                }
            }
            .navigationTitle("Boards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("New board", isPresented: $showNewBoard) {
                TextField("Board name", text: $newBoardName)
                Button("Cancel", role: .cancel) {}
                Button("Create") {
                    model.createBoard(named: newBoardName)
                    Task { await reload() }
                }
            }
            .alert("Rename board", isPresented: renamePresented) {
                TextField("Board name", text: $renameField)
                Button("Cancel", role: .cancel) {}
                Button("Rename") {
                    if let renameTarget { model.renameBoard(renameTarget, name: renameField) }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task { await reload() }
    }

    private var renamePresented: Binding<Bool> {
        Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
    }

    @ViewBuilder
    private func boardRow(_ board: Pinboard) -> some View {
        Button {
            open(board.id)
        } label: {
            boardLabel(
                board.isSystem ? Text("Favorites") : Text(verbatim: board.name),
                icon: BoardDot(board: board, size: 14), tint: .primary,
                count: counts[board.id] ?? 0)
        }
        .tint(.primary)
        .accessibilityIdentifier("boards-home-\(board.id.uuidString)")
        .contextMenu {
            if !board.isSystem { boardActions(board) }
        }
        .swipeActions(edge: .trailing) {
            if !board.isSystem {
                Button(role: .destructive) {
                    delete(board)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                Button {
                    renameField = board.name
                    renameTarget = board
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                .tint(.blue)
            }
        }
    }

    @ViewBuilder
    private func boardActions(_ board: Pinboard) -> some View {
        Button {
            renameField = board.name
            renameTarget = board
        } label: {
            Label("Rename board", systemImage: "pencil")
        }
        Button(role: .destructive) {
            delete(board)
        } label: {
            Label("Delete board", systemImage: "trash")
        }
    }

    private func boardLabel(
        _ title: Text, icon: some View, tint: Color, count: Int
    ) -> some View {
        HStack(spacing: GanchoTokens.Spacing.sm) {
            icon.frame(width: 22)
            title.foregroundStyle(tint)
            Spacer(minLength: GanchoTokens.Spacing.sm)
            Text("\(count)").foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private func open(_ id: UUID?) {
        model.selectBoard(id)
        dismiss()
    }

    private func delete(_ board: Pinboard) {
        model.deleteBoard(board)
        Task { await reload() }
    }

    private func reload() async {
        await model.refreshBoards()
        totalCount = await model.clipCount()
        var fresh: [UUID: Int] = [:]
        for board in model.boards { fresh[board.id] = await model.clipCount(in: board) }
        counts = fresh
    }
}
